# Measured native build identity

The current comparison uses native application commit
`e4f09c8af0795a86dad562dfbea3c6225f9d9a2c` for both capture APIs. Test tools and
documentation have later commits. Build identity and passed unit tests do not
establish resource budgets or a final backend choice.

The baseline is unmodified upstream commit
`7d644774045429a98c07678df553b771e3b5d129`, built with the same recorded runner
image, MSVC tools, MSBuild, vcpkg tool and Release/x64/Dev configuration. Its
original CI archive was also downloaded and matched to the measured executable
by SHA-256; its 81 native tests pass. The two additional native tests in the
Dynamic build cover its configuration/model behavior.

The [machine-readable receipts](dynamic-builds.json) identify the exact
executables and original CI archives by SHA-256. Both build logs were checked
for the native commit, actual backend argument, 83 passing native tests,
2,021 portable checks and the uploaded artifact digest.

| Candidate | Native build run | Build job |
| --- | --- | --- |
| Original baseline | [39546822333](https://github.com/arturito-agent/TranslucentTB/actions/runs/39546822333) | 119046761221 |
| GDI | [39594821980](https://github.com/arturito-agent/TranslucentTB/actions/runs/39594821980) | 119204425380 |
| DXGI | [39594825202](https://github.com/arturito-agent/TranslucentTB/actions/runs/39594825202) | 119204437086 |

## Recorded environment

| Component | Value |
| --- | --- |
| Hosted build OS | Windows Server 2025, 10.0.26100 |
| Runner family / image | windows-2025-vs2026 / 20261018.275.1 |
| MSBuild | 18.11.0.47511 |
| Observed MSVC tools directory | 14.51.36231 |
| Platform toolset | v145, Spectre mitigation enabled |
| Target / configuration | x64 / Release |
| Distribution identity | BuildType=Dev, unsigned portable executable |
| C++ language setting | stdcpplatest |
| Project target SDK | 10.0.28000.0 |
| NuGet | 7.0.1 |
| SDK CPP / BuildTools NuGet packages | 10.0.28000.2705 |
| C++/WinRT NuGet package | 3.0.260818.1 |
| WinUI NuGet package | Microsoft.UI.Xaml 2.8.7 |
| vcpkg tool commit | 664933b8d385dfc01f4e0cdff4c7c74e71f6a740 |
| vcpkg package registry baseline | 84bab45d415d22042bd0b9081aea57f362da3f35 |

Other NuGet versions are in the receipts and each project's `packages.config`.
The build uses the repository's `Common/vcpkg-configuration.json` and overlay
ports. The Windows 11 measurement VM is a separate environment; it did not
need Visual Studio installed.

## Rebuild a candidate

Use the workloads in `.vsconfig` and the upstream
[development instructions](../CONTRIBUTING.md). In a Windows developer shell
with the recorded build tools available:

```powershell
git checkout e4f09c8af0795a86dad562dfbea3c6225f9d9a2c
vcpkg integrate install
nuget restore TranslucentTB.slnx -NonInteractive -Source https://api.nuget.org/v3/index.json
msbuild TranslucentTB.slnx /m:1 /p:BuildInParallel=false /p:Configuration=Release /p:Platform=x64 /p:BuildType=Dev /p:AppxPackageSigningEnabled=false /p:AppxBundle=Never /p:DynamicBackend=GDI /v:minimal
```

Use `DynamicBackend=DXGI` for the other candidate. Serial MSBuild and disabled
parallel dependency computation match the measured builds. Keep package versions
and the vcpkg registry fixed when reproducing the comparison.

Hosted-runner images can change. These instructions reproduce the source and
configuration; they do not promise that a later toolchain emits identical PE
bytes. Identify published/measured binaries using their SHA-256 receipts.
The portable packager separately records the documentation commit and checks
the native executable hash before producing a ZIP.
