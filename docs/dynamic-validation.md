# Dynamic validation status

Experimental results as of 2026-10-21; the experiment is incomplete.

Current first-version functional closure on e4f09c8 passes all three mandatory
positions with each capture backend retaining the same process through
Bottom → Left → Right. The 36 exact-color cases and 30 Maximized Clear / Desktop
Dynamic stages are recorded in [the live-move receipt](dynamic-results/live-moves-e4f0.json).
Inactive stages show unchanged attempts and frames, a stopped capture timer and
no queued discovery timer. Both targets exit gracefully. These checks do not
establish resource budgets, contrast or prolonged stability.

Application revisions: upstream baseline
`7d644774045429a98c07678df553b771e3b5d129`, initial native validation
`3ea6890f1a7bf11b1b6bd8b44b6c819778458cb1`, lateral GDI/DXGI validation
`a6ad586fdd243f997058c79509b5328158ade6ed`, focus scheduling/counters
`a1b05b5840d48f29487fb1622091f576fb0505bb`, per-monitor ownership ad232a0,
refresh reconciliation `b46440a1f2feb5e5ce5538b7322bf1adbf60f7d2`, and current
tested application `753ad89ab3492098316a3015bbfc0a4539f415ba`.

The current source also gives each monitor a lazy capture instance, releasing
it when its appearance stops needing Dynamic. Previously, one shared DXGI
instance would recreate its device/duplication each time sampling switched
between outputs. Aggregate lifetime capture counters now survive destruction
of those instances. Revision ad232a0 passes both Windows builds, 83 native tests
and 2,021 portable checks; current 753ad89 includes that ownership change and
its live regression/color results are recorded below.
Measurements for a1b05b5 must not be presented as measuring the revised worker.
Multiple-display hardware is unavailable in this VM.

The a1b05b5 right/static resource series aborted during repetition two's GDI
phase. All 62 measured target observations report timer=0, paused=0, unchanged
45 attempts/frames and no capture failures. The driver closed the app/fixture
and restored its test configuration; the separate DWM observer was then stopped.
The eight completed earlier phases remain partial evidence, not a completed
three-repeat benchmark. No final backend choice or budget pass follows from them.

A bounded forced-composition-refresh/timer overlap reproduces a stop on a1b05b5:
timer 1 to 0 with paused=0, 77 refresh calls, 293 sent timer messages and no IPC
errors. The original spontaneous trigger was not recorded. Current source skips
sampling during temporary attribute suppression and reconciles timers after
restoring the previous suppression flag, including nested refreshes. The
[negative control](dynamic-results/refresh-race-a1b0.json) and
`Tests/dynamic/refresh-race.ps1` reproduce this mechanism. Revision with that fix
`b46440a1f2feb5e5ce5538b7322bf1adbf60f7d2` passes both Windows builds with
83 native tests and 2,021 portable checks each. Three six-second live regression
trials per backend on the real right classic taskbar all retain timer=1,
paused=0, increasing attempts and zero IPC errors. Both backends also pass the
six live color/continuity cases after the fix. These are diagnostic/functional
results; full resource measurements and prolonged stability remain pending.

The new b46440a right/static series started at 09:03:42 UTC with GPU collection
and the existing 120s/305s phase timing, but aborted in its first DXGI phase.
The first measured observation after warmup reports timer=0, paused=0,
44attempts,4frames,40timeouts and no capture failures. The early health gate
retained that observation and stopped immediately; its GPU observation was
never written. Three earlier phases form one completed GDI bracket, not three
repetitions. Driver, target, fixture and auxiliary observer were closed and
test settings restored. See the [failure receipt](dynamic-results/stopped-dxgi-b464.json).
The spontaneous trigger remains unknown; the earlier controlled race passing
does not prove this condition fixed.

That single GDI bracket estimates combined additional CPU of0.277354%of one
core: target0.074281%,Explorer0.012808%,DWM0.190265%. The point estimate exceeds
the initial0.1%static target; it is not a completed budget assessment or backend
selection. Combined private-commit difference is0.724609MiB. Retain all absolute
phase trajectories and finish the repetitions before drawing final conclusions.

A separate90second debug-logging follow-up retained91observations, all timer=1,
paused=0, with advancing attempts and no capture failures. The live configuration
remained Dynamic; its private debug log records only the initial state reset.
This failed to reproduce the intermittent stop and establishes no repair.
Revision51b47c3 added opt-in scalar scheduler snapshots to distinguish missing
taskbars, temporary suppression, configuration changes and timer creation
failures in the next diagnostic. That revision was instrumentation, not a fix.

Both51b47c3 builds pass83native tests and2021portable checks. The first90second
GDI VM observation with scheduler diagnostics remains active throughout and
reports no stops or timer creation failures. A second observation includes a
bounded controlled composition-refresh/policy-recompute overlap:79refresh calls,
296synthetic unlock notifications, no IPC errors, and64regular-timer stops with
attribute-suppression context bit4. It finishes active. The
[negative control](dynamic-results/policy-recompute-gdi-51b4-negative-r1.json)
demonstrates transient teardown, not the spontaneous permanent stop or an actual
session unlock. Revision 753ad89 separates shutdown from temporary reply
suppression so that recomputation keeps the active sampler's resources. Both
builds pass 83 native tests and 2,021 portable checks. The same old-policy
negative control also reproduces58transient stops with DXGI in6seconds, with
84refresh calls,254synthetic recomputations, suppression bit4 and zero IPC errors;
see its [receipt](dynamic-results/policy-recompute-dxgi-51b4-negative-r1.json).

Three six-second positive policy-overlap trials per backend on 753ad89 retain
active, unpaused sampling, advancing attempts, zero IPC errors and zero timer
stops. GDI refresh/recompute counts are 77/277, 76/275 and 75/273; DXGI counts
are 77/282, 76/276 and 78/286. The original forced-refresh/sent-timer regression
also passes once per backend, with zero stops. Both backends pass all six real
right-taskbar color cases. Each backend's separate 120-second observation has
121 target observations, all active, unpaused and with zero stops. These
controlled tests establish the transient-teardown fix; they do not establish
that the spontaneous permanent stop is resolved or that resource budgets pass.
See the [reviewed receipts](dynamic-results/README.md).

A separate current GDI inactive-mode check observes zero attempts and completed
frames with Desktop Clear. Deliberately requiring an active sampler rejects
that scene and verifies the collector's failure-only scheduler snapshot:
timer=0, paused=0, Desktop=Clear, context bit64. The app exits gracefully and its
configuration is restored. This validates diagnostics and inactive capture,
not display-off or actual session-lock behavior.

The extended five-phase right/static diagnostic on 753ad89 also passes. Every
phase observes 90 seconds after a two-second diagnostic warmup; actual taskbar
bounds remain (1218,0)..(1280,800), DPI 96. Both candidates retain active,
unpaused sampling, the exact static RGB and zero scheduler stops/creation
failures. GDI attempts and frames advance 8 to 184; DXGI attempts advance 8 to
183 and frames 3 to 7. All phase GPU streams match their CPU batch identity,
scope and QPC bounds. All five graceful exits, driver and fixture closure are
verified. See the [diagnostic receipt](dynamic-results/smoke-right-scheduler-753a.json).
This establishes five-restart sequencing and short sampler health, not a full
resource comparison or prolonged stability.

The first current GDI Maximized Clear test overlaps a delayed TaskbarCreated
broadcast from Explorer startup. Its last Dynamic stage samples correctly but
renders the known fallback after the worker's per-monitor state resets; the
test instead expects the earlier lifetime confirmed RGB and fails. A debug
repeat records the same overlap. After a 35-second shell preparation interval,
the unchanged five-stage assertion passes, with only the initial worker reset
in the debug log. This diagnoses a state-test precondition; it does not verify
all reconstruction recovery or change the application's rendering policy.
The [original overlap](dynamic-results/states-right-gdi-753a-startup-overlap.csv)
and [settled repeat](dynamic-results/states-right-gdi-753a-settled.csv) are retained.
The full current state matrix remains in progress.

The first Start state run correctly activates and stops sampling but fails the
pixel assertion at (1249,10). A separate point/owner diagnostic identifies that
point as the pressed `Start` button, RGB 5069158. The plain task-list background
at (1249,400) and the other tested background points is the expected fallback
RGB 2109504. The state harness now probes a fixed empty background location in
this few-window fixture and records the exact point/window class; the color
assertion remains exact. The revised helper compiles in the actual Windows VM;
all five revised GDI Start stages now pass, probing `MSTaskListWClass` at
(1249,400), with three active Dynamic stages and two stopped Clear stages.
The full positive state matrix described below subsequently passes. The
[failed leading-edge probe](dynamic-results/states-right-gdi-753a-start-button-probe.csv)
and [point diagnostic](dynamic-results/start-pixel-gdi-753a.json) remain available.
The [positive GDI Start receipt](dynamic-results/states-right-gdi-Start-753a.csv)
records the corrected point and exact assertion.

All ten current right-taskbar state cases now pass: Maximized Clear, title
rules, Start, Search and Task View, with both GDI and DXGI. Each records five
alternating stages: three Dynamic stages with advancing attempts and the exact
expected background pixel, and two Clear stages with a stopped timer and no
attempts during the observation window. Shell cases use actual keyboard
shortcuts, record foreground identity and verify the expected worker PID.
All ten app exits are graceful; the driver and its children finish and test
configuration is restored. The [matrix receipt](dynamic-results/states-right-753a.json)
pins the native revision and state helper hash. This verifies these cases on
the real right classic taskbar at 100%; it does not establish all menus,
battery saver, all rule forms, other positions or resource use.

Current GDI also passes a real Explorer restart while the candidate app remains
alive. It resumes active, unpaused sampling and exact blue taskbar rendering;
attempts and frames advance from 9 to 102. One timer stop occurs while no
taskbars are present, followed by recovery. The
[receipt](dynamic-results/explorer-recovery-gdi-753a.json) includes its verified
graceful app exit. The first DXGI recovery diagnostic aborts on an unavailable
protocol observation immediately after restarting Explorer; it writes no
recovery trajectory and establishes no result. That app exits gracefully and
settings are restored. A separate diagnostic now retains unavailable interim
queries, including their owner/status/error, and still requires valid final
counters, resumed capture and the exact taskbar pixel. That separate DXGI run
now passes, with 44 available protocol observations, attempts 8 to 48, completed
frames 3 to 6, exact blue rendering and a verified graceful exit. Its
[receipt](dynamic-results/explorer-recovery-dxgi-753a.json) retains 27 observations
with an empty taskbar map and stopped timer before recovery. The first newly
completed frame is observed about 32.0 seconds after the pre-restart snapshot,
versus 5.8 seconds for GDI. These are single recovery trials with about one-second
observation intervals, not latency percentiles or evidence of the cause of the
original unavailable query.

The parameterized recovery tool also passes on the actual left classic taskbar
with both backends, preserving (0,0)..(62,800) geometry at 96 DPI and confirming
exact blue rendering, resumed attempts/new frames and graceful exits. First
new frames are observed about 5.8s GDI and 4.7s DXGI after their pre-restart
snapshots. These remain single trials; the earlier 32s right DXGI observation
is retained rather than generalized to all DXGI recovery. See the
[left GDI](dynamic-results/explorer-recovery-left-gdi-753a.json) and
[left DXGI](dynamic-results/explorer-recovery-left-dxgi-753a.json) receipts.
Bottom recovery fails on GDI 753ad89: the real (0,760)..(1280,800) bar remains
visible with the old blue pixel, but the worker finishes with an empty map,
timer=0, paused=0 and 45 unchanged attempts/frames. This is a real failure;
the prior pixel alone would hide it. The driver closes its app/fixture and
restores configuration; DXGI is not run after that failure. The
[failed receipt](dynamic-results/explorer-recovery-bottom-gdi-753a-failed.json)
is retained. A later read-only query finds the classic taskbar children and
ExplorerPatcher module with no Taskbar.dll loaded, but this does not establish
the exact transient detection reason at the earlier worker reset.

The proposed source fix performs at most five delayed discovery retries after
an empty-map reset when an enabled appearance/rule can use Dynamic. Delays are
0.5, 1, 2, 4 and 8 seconds; real shell/resume events can begin a new bounded
sequence. Discovery is canceled once the map is populated, all Dynamic options
are disabled, the display/session pauses or the app exits. It adds no steady
capture-rate increase or permanent watchdog. Scalar diagnostics distinguish
actual recovery attempts from a coincidental subsequent shell event. This
source revision e4f09c8 now passes both Windows builds, 83 native tests and
2,021 portable checks per backend. The first bottom recovery repeat also
passes with both verified binaries: exact blue, advancing attempts/new frames,
active unpaused sampling, graceful exit and no queued discovery timer/failures.
Both discovery request counters remain zero, so these successful nominal trials
do not exercise the delayed-retry path or prove the rare empty-map repair.
See [GDI](dynamic-results/explorer-recovery-bottom-gdi-e4f0.json) and
[DXGI](dynamic-results/explorer-recovery-bottom-dxgi-e4f0.json). Full resource
budgets and prolonged stability remain unverified.

All 24 new e4f09c8 left/bottom color cases pass: six patterns per position and
backend, comparing the independent expected RGB, confirmed worker RGB and an
actual taskbar pixel. The real left (0,0)..(62,800) and bottom
(0,760)..(1280,800) bounds remain consistent at 96 DPI. All four app exits are
graceful, the driver finishes, and test settings are restored. The
[matrix receipt](dynamic-results/functional-matrix-e4f0.json) pins both binary
hashes; the corresponding CSVs retain every color/run-length observation.
These verify exact colors and geometry, not resource budgets or glyph contrast.

Test-tool revision1851bbf separately passes Windows PowerShell fixture compilation,
read-only counter queries, static/animated lifecycle checks, GPU accounting tests
and an actual short collector/summary on a hosted Windows Server2025 runner.
The [fixture receipt](dynamic-results/fixture-check-ci-1851.json) records zero
static animation ticks and53ticks per animated case over about2.5seconds.
These are callback counts, not presented frames or VM product resource results.
The separate local VM workload preflight now also passes: Uniform has zero
animation ticks and one paint; Changing records52ticks/53paints over2553ms,
Interaction53ticks/55paints over2573ms. The [VM receipt](dynamic-results/fixture-check-vm-1851.json)
records the executed script hash and canonical source verification. These are
callback counts, not presented frames or product resource results. Full
Changing/Interaction suites and their per-phase workload-rate checks remain pending. Tool revision4fb2266 also passes the compile-only
shell helper/INPUT layout check, all8Python analysis checks, actual short metric
collection and2021portable checks on Windows CI; live shell/browser checks remain
pending on the local VM.

## Environment

Windows 11 Enterprise LTSC Evaluation 24H2, build 26100.8875, two logical
processors, 6 GiB guest RAM, Microsoft Basic Display Adapter 10.0.26100.1,
1280x800 single SDR display at 100% scale, reported 64Hz/32bpp and Balanced power.
Display enumeration exposes only that resolution. GPU engine and per-process
graphics-memory counters are available through PDH; this does not establish
physical-GPU efficiency or power use. Internal SPICE console attached;
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
The first full right/static series aborted as described above; no resource
budget or backend winner has been established yet.

The revised worker and collector also completed a new five-phase right/static
smoke with GPU recording and the early Dynamic health gate enabled. All target
observations retain the real right rectangle (1218,0)..(1280,800); both candidates
have active unpaused sampling and completed frames. All five phase receipts and
GPU streams exist; GPU scope/status checks pass, and driver/fixture/apps are
confirmed closed afterwards. This is a short orchestration check, not a resource
benchmark or prolonged stability result. Full new series remain required.

## Still required

Remaining bottom coverage, 150% DPI, complete state/menu/rule integration,
session lock and Explorer recovery, internal-content latency at the final
revision, full
bracketed resource measurements and the 60-minute stability session. Multiple
displays/HDR are unavailable in the current setup. Classic glyph contrast needs
a validated implementation before claiming complete lateral appearance support.
No CPU, memory, battery, energy or universal compatibility result is claimed.
