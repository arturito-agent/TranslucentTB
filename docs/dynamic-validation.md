# Dynamic validation status

Experimental results as of 2026-10-21; the experiment is incomplete.

Application revisions: upstream baseline
`7d644774045429a98c07678df553b771e3b5d129`, initial native validation
`3ea6890f1a7bf11b1b6bd8b44b6c819778458cb1`, current GDI/DXGI builds
`a6ad586fdd243f997058c79509b5328158ade6ed`; current focus-scheduling and
capture-counter revision `a1b05b5840d48f29487fb1622091f576fb0505bb`.

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

Both a6ad586 backends also pass all six color cases on a real right taskbar
(62x800 pixels, rectangle x=1218..1280); the winning blue run is 320 steps.
The GDI display-off test on that taskbar observes a stopped timer, paused flag,
and unchanged attempt count (415 to 415) over three seconds. A physical console
screenshot is black. After a console key wakes the display, the timer resumes,
the pause flag clears and the attempt count advances to 425. Session lock and
other recovery cases remain untested.

Both a1b05b5 backends pass the six right-taskbar color cases. GDI a6ad586 also passes
those cases after a live 100% to 125% scale change: the real bar grows from
62 to 78 physical pixels, with a 1280x800 monitor. The original 100% scale was
restored. At this resolution, Windows offers only 100% and 125% in its normal
selector. Custom 150% and session-lock testing need a subsequent interactive
sign-in and remain pending.

Five Desktop Dynamic / Maximized Clear transitions and five visible-window
title-rule Dynamic / Clear transitions pass on a6ad586 and a1b05b5 (GDI).
Clear stages have no attempts after the state settles; Dynamic stages sample
and apply either the confirmed color or the configured fallback. See the
[raw synthetic evidence](dynamic-results/README.md).

Preliminary a6ad586 latency observations: 30 left DXGI focus trials have p95
1.067s; 30 right GDI focus trials with deterministic interval variation have p95
1.051s. Both slightly exceed the initial 1s focus target; the 50ms observer
quantization is included. A coalesced foreground-triggered deferred sample is
now implemented for validation, retaining the 500ms steady timer and shared
200ms minimum. With a1b05b5, 30 right-taskbar focus trials per backend yield:

| Backend | Median | p95 | Maximum |
| --- | --- | --- | --- |
| GDI | 0.739s | 0.923s | 0.939s |
| DXGI | 0.708s | 0.955s | 1.098s |

These use deterministic interval variation, 50ms observation quantization and
nearest-rank p95. Both meet the initial focus p95 target in this run; the DXGI
maximum exceeds one second and is retained. This is not a universal latency
guarantee. [CSV and summary](dynamic-results/focus-latency-a1b0.json) are included.
Interaction CPU cost is still unmeasured.

DXGI a1b05b5 also passes real display-off/resume: both attempts (1271) and
completed frames (97) stay unchanged while paused; after a console-key wake,
they increase to 1311 and 101. The completed-frame count survives resource reset.

DXGI initially timed out while the virtual display was powered off. With the
display actually awake, its first probe frame was black, subsequent frames
matched GDI, and all six live left-taskbar color cases passed. Treat display
state and warmup as experimental controls, not evidence of API incompatibility.

## Build verification

- Untouched baseline: 81 native tests pass.
- GDI/DXGI a6ad586: both Release x64 builds pass 83 native tests and 2,021
  standalone algorithm/geometry/stability checks.
- Both a1b05b5 builds also pass 83 native and 2,021 standalone checks.
- Linux portable checks pass optimized warnings-as-errors and ASan/UBSan.
- Short orchestration smoke completed five phases with graceful target exits;
  it is not a resource benchmark and used the same GDI build for both candidate
  slots solely to test sequencing.

An additional two-backend smoke verified metrics, capture counters and the
separate DWM CPU stream. It also exposed an experimental control issue:
ExplorerPatcher's live lateral position reverts after a forced Explorer restart.
Those phase position labels are unverified and must not be used as lateral
benchmark evidence. The driver now reapplies the position through the reviewed
release's own [GUI position message](https://github.com/valinet/ExplorerPatcher/blob/26100.8457.70.3/ep_gui/GUI.c),
refits the owned fixture, and checks/records actual geometry after each restart
and in every collected sample. The corrected five-phase smoke passed: all target
observations report the actual right rectangle (1218,0)..(1280,800).
The first full right/static series is now running with three repetitions; no
resource budget or backend winner has been established yet.

## Still required

Remaining bottom coverage, 150% DPI, complete state/menu/rule integration,
session lock and Explorer recovery, internal-content latency at the final
revision, full
bracketed resource measurements and the 60-minute stability session. Multiple
displays/HDR are unavailable in the current setup. Classic glyph contrast needs
a validated implementation before claiming complete lateral appearance support.
No CPU, memory, battery, energy or universal compatibility result is claimed.
