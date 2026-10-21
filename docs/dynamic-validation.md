# Dynamic validation status

Experimental results as of 2026-10-21; the experiment is incomplete.

Application revisions: upstream baseline
`7d644774045429a98c07678df553b771e3b5d129`, initial native validation
`3ea6890f1a7bf11b1b6bd8b44b6c819778458cb1`, current GDI/DXGI builds
`a6ad586fdd243f997058c79509b5328158ade6ed`.

## Environment

Windows 11 Enterprise LTSC Evaluation 24H2, build 26100.8875, two logical
processors, 6 GiB guest RAM, Microsoft Basic Display Adapter 10.0.26100.1,
1280x800 single SDR display at 100% scale. Internal SPICE console attached;
synthetic fixture requests display-on while running. The application itself
does not prevent display sleep. The guest remains offline. Desktop VC++ runtime
14.51.36247 is installed. The guest's UTC wall-clock interpretation differs
from host UTC by two hours; elapsed measurements use monotonic QPC/Stopwatch.

ExplorerPatcher 26100.8457.70.3 supplies the real lateral Windows 10 taskbar.
Its official release SHA-256 was verified before installation. On this offline
guest it reports unavailable symbol downloads; the reimplemented taskbar and
left-position setting nevertheless work. No Defender, UAC or Smart App Control
policy was weakened. Restore the original taskbar settings after testing.

## Verified behavior

| Check | Modern bottom, GDI 3ea6890 | Classic left, GDI a6ad586 | Classic left, DXGI a6ad586 |
| --- | --- | --- | --- |
| Longest contiguous run beats greater global frequency | Pass | Pass | Pass |
| Unreliable noise retains last valid color | Pass | Pass | Pass |
| Exact light RGB 248,248,248 | Pass | Pass | Pass |
| Exact dark RGB 16,16,16 | Pass | Pass | Pass |
| Exact uniform RGB 32,96,160 | Pass | Pass | Pass |
| Two-pixel boundary excluded | Pass | Pass | Pass |
| System glyph contrast on light background | Pass | Visually pending | Visually pending |
| System glyph contrast on dark background | Pass | Fails: follows system theme | Same classic limitation |
| Native Dynamic menu | Pass | Pending full menu/state audit | Pending full menu/state audit |
| Selection/fallback persistence after graceful restart | Pass | Pending | Pending |
| Restore prior background on graceful exit | Pass, exact pixel match | Pending full audit | Pending full audit |

Color checks compare internal confirmed RGB with a pixel on the real taskbar.
They do not by themselves verify glyph contrast or every state/rule. The left
bar was 62x800 physical pixels; the winning blue run was 320 steps versus two
separated red runs totaling 480. Static noise did not increase the confirmed
change/application count. A generic per-window DarkMode_Explorer theme probe did
not correct classic glyphs and is not part of the product implementation.

DXGI initially timed out while the virtual display was powered off. With the
display actually awake, its first probe frame was black, subsequent frames
matched GDI, and all six live left-taskbar color cases passed. Treat display
state and warmup as experimental controls, not evidence of API incompatibility.

## Build verification

- Untouched baseline: 81 native tests pass.
- GDI/DXGI a6ad586: both Release x64 builds pass 83 native tests and 2,021
  standalone algorithm/geometry/stability checks.
- Linux portable checks pass optimized warnings-as-errors and ASan/UBSan.
- Short orchestration smoke completed five phases with graceful target exits;
  it is not a resource benchmark and used the same GDI build for both candidate
  slots solely to test sequencing.

## Still required

Right and remaining bottom coverage, 150% DPI, state/rule integration, real
display-off/lock/resume and Explorer recovery, latency distributions, full
bracketed resource measurements and the 60-minute stability session. Multiple
displays/HDR are unavailable in the current setup. Classic glyph contrast needs
a validated implementation before claiming complete lateral appearance support.
No CPU, memory, battery, energy or universal compatibility result is claimed.
