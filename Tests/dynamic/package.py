"""Package a verified CI runtime without settings, logs or build intermediates."""
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    metadata = json.loads((args.runtime / "BUILD.json").read_text())
    if metadata["backend"] not in ("GDI", "DXGI"):
        raise ValueError("Unknown capture backend")
    if not re.fullmatch(r"[0-9a-f]{40}", metadata["commit"]):
        raise ValueError("Use the complete tested native commit")
    names = ["TranslucentTB.exe", "ExplorerHooks.dll", "ExplorerTAP.dll",
             "ProgramLog.dll", "Xaml.dll", "resources.pri", "AppxManifest.xml",
             "Assets/SplashScreen.jpeg", "Assets/SplashScreen.scale-400.jpeg"]
    files = {}
    for name in names:
        path = args.runtime / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing regular runtime file: {name}")
        files[name] = path.read_bytes()
    if digest(files["TranslucentTB.exe"]) != metadata["executable_sha256"]:
        raise ValueError("Executable differs from the verified build receipt")
    documentation_commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "docs",
                    "LICENSE.md", "CONTRIBUTING.md"], cwd=root, check=True)
    for name in subprocess.check_output(
            ["git", "ls-files", "docs"], cwd=root, text=True).splitlines():
        if Path(name).suffix in (".md", ".json", ".csv"):
            files[name] = (root / name).read_bytes()
    if "docs/dynamic-install.md" not in files:
        raise ValueError("Commit the installation instructions before packaging")
    for name in ("LICENSE.md", "CONTRIBUTING.md"):
        files[name] = (root / name).read_bytes()
    allowed = ("commit", "backend", "run", "artifact", "archive_sha256",
               "executable_sha256", "native_tests_passed", "portable_checks_passed")
    public_build = {name: metadata[name] for name in allowed}
    public_build["documentation_commit"] = documentation_commit
    files["BUILD.json"] = (json.dumps(public_build, indent=2) + "\n").encode()
    files["README.md"] = (
        "# TranslucentTB Dynamic experiment\n\n"
        "Read [installation and use](docs/dynamic-install.md) before running.\n\n"
        f"Native source: https://github.com/arturito-agent/TranslucentTB/tree/{metadata['commit']}\n\n"
        f"Capture backend: {metadata['backend']}. See BUILD.json and SHA256SUMS.\n"
    ).encode()
    files["SHA256SUMS"] = "".join(
        f"{digest(data)}  {name}\n" for name, data in sorted(files.items())
    ).encode()
    # Fixed entry timestamps and ordering make identical inputs reproducible.
    with zipfile.ZipFile(args.output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo("TranslucentTB-Dynamic/" + name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    print(f"{digest(args.output.read_bytes())}  {args.output.name}")


if __name__ == "__main__":
    main()
