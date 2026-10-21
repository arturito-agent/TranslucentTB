"""Compare each candidate with its adjacent baseline phases in a complete suite."""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from statistics import median

from summarize import dwm_cpu, read, summarize


LABEL = re.compile(r"^(Bottom|Left|Right)-(Static|Interaction|Changing)-r([1-3])-p([0-4])-(baseline|gdi|dxgi)$")


def describe(values):
    if any(value is None for value in values):
        return {"median": None, "minimum": None, "maximum": None, "values": values}
    return {"median": median(values), "minimum": min(values), "maximum": max(values), "values": values}


def subtract_bracket(candidate, before, after):
    if any(value is None for value in (candidate, before, after)):
        return None
    return candidate - (before + after) / 2


def load_phase(path, auxiliary):
    rows = read(path)
    if not rows:
        raise ValueError(f"Empty phase: {path}")
    match = LABEL.fullmatch(rows[0]["label"])
    if not match or path.stem != rows[0]["label"]:
        raise ValueError(f"Invalid full-suite label: {path}")
    position, workload, repeat, phase, backend = match.groups()
    groups = defaultdict(list)
    for row in rows:
        if row["label"] != path.stem or row.get("taskbar_edge") != position:
            raise ValueError(f"Label or measured geometry mismatch: {path}")
        groups[(row["role"], row["pid"])].append(row)
    roles = {}
    for (role, _), group in groups.items():
        if role in roles:
            raise ValueError(f"Process restarted during phase: {path}, {role}")
        group.sort(key=lambda row: int(row["qpc_ticks"]))
        item = summarize(group, False)
        if role == "compositor" and auxiliary:
            item["separate_observer_cpu"] = dwm_cpu(auxiliary, group[0], group[-1])
            item["cpu_one_core_percent"] = item["separate_observer_cpu"]["cpu_one_core_percent"]
        roles[role] = item
    for role in ("target", "shell", "compositor"):
        if role not in roles:
            raise ValueError(f"Missing process role: {path}, {role}")
    return (position, workload, int(repeat), int(phase), backend), roles


def compare(directory, auxiliary):
    if (directory / "status.txt").read_text(encoding="utf-8-sig").strip() != "complete":
        raise ValueError("Only complete suites can establish resource results")
    if (directory / "error.txt").exists():
        raise ValueError("Suite has an error receipt; investigate before comparing")
    phases = {}
    receipts = {}
    setting = None
    for path in sorted(directory.glob("*.csv")):
        key, roles = load_phase(path, auxiliary)
        current = key[:2]
        if setting is not None and setting != current:
            raise ValueError("A suite must contain one position/workload")
        setting = current
        phase_key = key[2:4]
        if phase_key in phases:
            raise ValueError("Duplicate phase")
        receipt = json.loads(path.with_suffix(".json").read_text(encoding="utf-8-sig"))
        if receipt.get("diagnostic_only") or receipt.get("warmup_seconds", 0) < 120:
            raise ValueError("Missing full warmup or diagnostic-only phase")
        source_rows = read(path)
        if receipt.get("label") != path.stem or any(row["commit"] != receipt.get("commit") for row in source_rows):
            raise ValueError("Receipt label/commit does not match measurement")
        phases[phase_key] = (key[-1], roles)
        receipts[phase_key] = receipt
    if len(phases) != 15:
        raise ValueError("Expected all fifteen full phases")
    comparisons = []
    for repeat in range(1, 4):
        expected = ("baseline", "gdi", "baseline", "dxgi", "baseline") if repeat % 2 else ("baseline", "dxgi", "baseline", "gdi", "baseline")
        if tuple(phases[(repeat, phase)][0] for phase in range(5)) != expected:
            raise ValueError("Unexpected candidate order")
        for phase in (1, 3):
            backend, candidate = phases[(repeat, phase)]
            before, after = phases[(repeat, phase - 1)][1], phases[(repeat, phase + 1)][1]
            deltas = {}
            for role in ("target", "shell", "compositor"):
                deltas[role] = subtract_bracket(*(item[role]["cpu_one_core_percent"] for item in (candidate, before, after)))
            if any("taskbar-helper" in item for item in (candidate, before, after)):
                deltas["taskbar-helper"] = subtract_bracket(*(item["taskbar-helper"]["cpu_one_core_percent"] if "taskbar-helper" in item else 0 for item in (candidate, before, after)))
            total = None if any(value is None for value in deltas.values()) else sum(deltas.values())
            private_deltas = {}
            for role in deltas:
                values = [item[role]["private_bytes"]["median"] if role in item else 0 for item in (candidate, before, after)]
                difference = subtract_bracket(*values)
                private_deltas[role] = None if difference is None else difference / 1048576
            private_total = None if any(value is None for value in private_deltas.values()) else sum(private_deltas.values())
            comparisons.append({"repeat": repeat, "backend": backend, "candidate_phase": phase,
                                "cpu_delta_one_core_percent": deltas, "combined_cpu_delta_one_core_percent": total,
                                "target_private_delta_mib": private_deltas["target"],
                                "private_delta_mib": private_deltas, "combined_private_delta_mib": private_total,
                                "absolute_roles": candidate})
    aggregates = {}
    for backend in ("gdi", "dxgi"):
        items = [item for item in comparisons if item["backend"] == backend]
        aggregates[backend] = {
            "combined_cpu_delta_one_core_percent": describe([item["combined_cpu_delta_one_core_percent"] for item in items]),
            "target_private_delta_mib": describe([item["target_private_delta_mib"] for item in items]),
            "combined_private_delta_mib": describe([item["combined_private_delta_mib"] for item in items]),
            "private_delta_mib": {role: describe([item["private_delta_mib"].get(role, 0) for item in items])
                                  for role in sorted(set().union(*(item["private_delta_mib"] for item in items)))},
            "cpu_delta_one_core_percent": {role: describe([item["cpu_delta_one_core_percent"].get(role, 0) for item in items])
                                            for role in sorted(set().union(*(item["cpu_delta_one_core_percent"] for item in items)))}}
    return {"position": setting[0], "workload": setting[1], "repetitions": 3,
            "method": "candidate minus arithmetic mean of adjacent baselines; CPU in percent of one logical core",
            "limits": ["A bracketed difference estimates incremental cost; it is not a causal guarantee or confidence interval.",
                       "Combined CPU includes target, Explorer, DWM and a taskbar helper when present; workload, harness and observers remain separate.",
                       "Private-memory differences use each process's phase median; combined private commit excludes shared working sets and is not a measurement of GPU allocations.",
                       "Inspect absolute phase trajectories for retained allocator/device memory after a candidate exits; bracketing does not remove carryover.",
                       "Ranges show three repetition results; negative differences are retained, not clamped."],
            "aggregates": aggregates, "comparisons": comparisons,
            "phase_summaries": [{"repeat": key[0], "phase": key[1], "backend": backend,
                                 "receipt": receipts[key], "absolute_roles": roles}
                                for key, (backend, roles) in sorted(phases.items())]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--dwm-observer", type=Path)
    args = parser.parse_args()
    auxiliary = read(args.dwm_observer) if args.dwm_observer else []
    print(json.dumps(compare(args.directory, auxiliary), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
