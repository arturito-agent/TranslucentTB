# Dynamic appearance (experimental)

Dynamic is a native appearance option alongside Normal, Opaque, Clear, Blur and
Acrylic. Select it separately for Desktop, Visible window, Maximized window,
Start opened, Search opened, Task View opened or Battery saver. Existing
appearance selection and application rules determine which monitor needs it.
In JSON, set `"accent": "dynamic"` on any supported appearance or rule.

This is an experiment in progress. The native menu, bottom-taskbar color,
configuration persistence and exit restoration were exercised on Windows 11
26100.8875 with revision 3ea6890. Revision a6ad586 passes the six synthetic
color/continuity cases on real left/right taskbars with both GDI and DXGI;
a1b05b5 also passes the right cases and 30 focus-latency trials per backend. Classic
taskbar glyph contrast still follows the system theme and fails on some dark
backgrounds. See [validation status](dynamic-validation.md). Full integration
coverage and benchmarks remain pending. No performance result is claimed.

## Sampling and selection

Read a four-physical-pixel strip two physical pixels outside the actual taskbar.
The strip spans the monitor's full width (bottom) or height (left/right). Top
taskbars are out of scope. Invalid geometry/capture retains the last valid
color. The appearance's Accent Color is the configurable initial fallback;
alpha is forced to 255 in Dynamic and does not change the selected RGB.

Each step groups its four pixels into fixed RGB buckets of width four per
channel. The largest bucket wins; ties prefer the previous output's bucket,
then the first pixel in cross-strip order. Average only that bucket's pixels.
Scan the resulting representatives for the longest contiguous equal-bucket
run. Do not add separated runs. Ties prefer the previous output's bucket,
then the first run. The final RGB is the integer mean of run representatives.
Fixed buckets prevent drift across a gradient.

Require at least eight steps and 1% of the edge. Require the candidate bucket
on two observations at least 200 ms apart; same-bucket fluctuations retain
the prior output. The steady scheduler samples every 500 ms with timer
coalescing. Foreground changes and activation of Dynamic request one additional
deferred sample after 200 ms, coalescing event bursts. All paths share a 200 ms
minimum between attempts. Window events never capture pixels synchronously.
Sampling only applies changed colors. Explorer
invalidations may reapply cached colors. Sampling stops when no effective
appearance is Dynamic, the session locks, or the display turns off.
Sampling skips temporary attribute suppression during forced composition
refreshes; timer state is reconciled when the previous suppression flag returns.
Capture resources are created lazily per monitor and released when that
monitor no longer needs Dynamic. This also keeps each DXGI output's duplication
and cached strip separate. Lifetime diagnostic totals remain in the worker
when a capture is released or Explorer is rebuilt. Multiple-display behavior
still requires hardware validation; the current VM has one display.

The first backend is BitBlt into a reused top-down DIB with GdiFlush before
direct CPU reads. Analysis uses constant auxiliary memory and linear time.
There is no permanent helper process. Application-only appearance values are
translated before entering Windows composition APIs.

## Build and tests

Use the upstream [build instructions](../CONTRIBUTING.md), Release x64. Portable
execution also requires a desktop Visual C++ v14 x64 runtime at least as recent
as the compiler, in addition to the WinUI/UWP framework dependencies. Obtain the
official package from [Microsoft's supported runtime downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/).
The
`Dynamic Windows build` workflow builds the pinned upstream baseline and this
branch with the same runner family and configuration, then uploads test output
and Windows artifacts. It does not sign or publish installers. Runner/image and
dependency revisions must be retained with measurements.

Pushes build Dynamic; manual dispatch can select `baseline` or `both`. MSBuild
runs serially to avoid C++/WinRT's parallel dependency computation cycle, which
was also observed on the untouched upstream baseline.

The platform-independent geometry, run-selection and stability tests also run
without Windows or third-party dependencies:

```sh
g++ -std=c++20 -O2 -Wall -Wextra -Werror -pedantic -I Common \
  Tests/dynamic/standalone.cpp -o dynamic-tests
./dynamic-tests
```

Configuration/WinRT round-trip tests run in the existing Windows test suite.
The test executable's activation manifest resolves the local Xaml.dll model;
it does not register the application globally.
The final experiment report will record actual Windows behavior, compatibility,
resource use, capture-backend comparison and remaining limitations.

## Comparison backend and diagnostics

Build with `/p:DynamicBackend=DXGI` to select the comparison implementation.
The default remains GDI. DXGI duplicates the monitor output and copies only the
sample rectangle into a reusable staging texture, handling timeout and device
loss. Rotated outputs are currently unsupported in the experimental DXGI path.
`capture-probe.exe` checks GDI and DXGI availability on the actual desktop,
printing HRESULTs and selected colors without modifying the taskbar.

`Tests/dynamic/fixture.ps1` creates only synthetic patterns. Run it in the
interactive session; Escape closes it. Choose Vertical orientation for lateral
taskbars. Changing content repaints a moving band on a blue/red background at
a nominal 33ms interval; its dominant color changes every two seconds.
Interaction continuously moves/resizes a second window, with slower focus and
color transitions. Frame work runs in the native WinForms message loop rather
than a PowerShell callback on every frame. Static patterns have no animation.
Read-only fixture counters record actual animation ticks and paints separately;
these are not a measurement of monitor presentation FPS. The collector reports
their rates under the workload role, and full non-static suites reject a stalled
fixture (at most five animation ticks/s or no paint progression). Inspect actual
rates across all phases before interpreting a comparison. The receipt pins the
fixture hash and nominal intervals. This update must be preflighted before its
first full VM series; the already-running right/static series keeps its original
fixture and collector without these additional counters.

The fixture uses physical-pixel DPI awareness and keeps its display on
for repeatability; `-AllowDisplaySleep` disables that test-only power request.
Production Dynamic itself never prevents screen sleep. `measure.ps1` collects bounded process
observations to a specified CSV after a warmup. Keep fixture, measurement
configuration and visualization connection unchanged between compared runs.
These are experiment tools, not permanent runtime helpers.
Start tests with the actual console awake and unlocked. A display-on power
request holds an already-awake virtual display; it does not reliably wake one
that is already off. A console key supplies that wake. Paused runs are rejected.
The adjacent strip includes visible window frames and scrollbars, which can
determine its color.

For a real browser content check, open `Tests/dynamic/browser-fixture.html` as a
local file in Edge after resource measurements finish. Its centered controls
stay away from the adjacent edge. Scroll advances four full-height synthetic
sections; Change theme repaints the same focused window; Start scroll cycle
advances every 3.5 seconds. All content is local and requires no network.
Play video uses an optional `dynamic-video.webm` beside the HTML. Generate the
synthetic 16-second, 30fps clip on the host outside measured intervals:

```sh
ffmpeg -f lavfi -i 'color=c=0xf8f8f8:s=640x360:r=30:d=4' \
  -f lavfi -i 'color=c=0x101010:s=640x360:r=30:d=4' \
  -f lavfi -i 'color=c=0x2060a0:s=640x360:r=30:d=4' \
  -f lavfi -i 'color=c=0xf00000:s=640x360:r=30:d=4' \
  -filter_complex '[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[v]' \
  -map '[v]' -an -c:v libvpx -b:v 200k -deadline good -cpu-used 4 \
  local-files/dynamic-video.webm
```

Copy the clip beside the guest's HTML; keep generated media in ignored local
files on the host. Codec color conversion can shift RGB: compare the actual
decoded adjacent strip, not the encoder's input palette. These browser checks
are separate from the resource suite and do not themselves establish latency
percentiles or resource budgets. Record failures and actual taskbar geometry.

For repeatable browser inspection, attach Playwright CLI to that owned Edge
instance through a private CDP transport and an isolated fixture profile. Keep
CLI artifacts under ignored `local-files/` using its `outputDir` configuration.
`browser-state.js` is a read-only `run-code --filename` helper: it refuses other
page titles/URLs and reports focus, scroll position, edge CSS, playback progress,
decoded/dropped frame counters and an optional decoded center pixel. Example,
after preparing the endpoint and local output configuration:

```sh
playwright-cli -s=ttb-dynamic-browser attach --cdp="$TTB_CDP_ENDPOINT" --config=local-files/browser-cli.json
playwright-cli -s=ttb-dynamic-browser --raw run-code --filename=Tests/dynamic/browser-state.js
playwright-cli -s=ttb-dynamic-browser detach
```

Use the page's actual Scroll/Change theme/Play video buttons between observations.
If canvas readback is unavailable, the helper preserves its error; keep browser
security settings intact. Pair these DOM observations with the real desktop
reference and taskbar pixels. `DynamicStateTest.ReferencePixel()` samples the
middle of the adjacent strip for uniform browser scenes, while `TaskbarPixel()`
reads the real bar. Both require physical-pixel DPI context; the helper is defined
by `states.ps1 -CompileOnly`. A single reference point is not an oracle for
arbitrary segmented content; use the separate continuity cases for that.
Browser wall-clock timestamps can correlate functional observations in the guest;
its page-relative performance clock is not Windows QPC. This workflow still
awaits its first real Windows 11 browser execution after the active resource run.

`functional.ps1` verifies six scenes against both the worker's chosen RGB and
the actual taskbar pixel. `latency.ps1` measures internal-content or foreground
switches with a 50ms polling observer; run it separately from resource trials.
`benchmark.ps1` validates hashes from a three-build JSON manifest and executes
baseline/candidate/baseline phases, alternating GDI/DXGI order over three
repeats. It gracefully closes each target and restores the prior test-build
configuration. Its `-Smoke` mode uses short intervals labeled SMOKE and is only
an orchestration check. Normal mode requires 120s warmup and at least 300s
measured per phase. Explorer is restarted identically before every phase because
the injected service remains pinned until its process exits. Keep an unrelated
Windows desktop controller's shell/virtual-desktop references fresh afterwards.
For the intermittent-stop investigation, `-Smoke -SmokeDurationSeconds 90
-IncludeScheduler` keeps the same fixture-before-Explorer-restart sequence but
observes each phase longer. Candidate builds must expose scheduler diagnostics.
The default smoke duration remains five seconds; the bounded override accepts
one through120seconds and cannot change normal full-measurement timing. These
SMOKE phases remain diagnostic-only and cannot establish resource budgets.
Lateral runs use `taskbar-position.ps1` with the reviewed ExplorerPatcher
26100.8457.70.3 private position message. The driver checks its version/module,
reapplies the real edge after each Explorer restart and refits the owned fixture.
Every CSV batch records physical taskbar bounds, edge and DPI. A phase with a
different edge, paused/stopped sampling, failed captures or incorrect static
reference color is rejected. `states.ps1` checks the documented state/rule
configurations, including fallback use on unreliable native window frames.
Its Start/Search/TaskView cases use real Windows shortcuts to alternate the
actual shell view open/closed, with Desktop Clear and only that view's Dynamic
override enabled. Pass the known application PID with `-ExpectedProcessId`;
the test verifies worker ownership and protocol before sending input, requires
its own fixture to be foreground before opening a view, and closes an owned
requested view on cleanup. It records sampler progress, foreground window class
and the real taskbar pixel. Run these cases only in the unlocked interactive
session outside measured resource intervals. `-CompileOnly` checks the native
helper/INPUT layout without sending input; it does not establish live shell
integration. The first local VM execution of these new cases is still pending.

The collector includes a final endpoint, checks an optional target PID, keeps
the observer's costs separate, and leaves unavailable metrics empty with an
error reason instead of omitting the process or reporting zero. Protected DWM
CPU counters may need a separate elevated read-only observer. The instance can
be queried or closed gracefully with `session.ps1`, which checks its executable
path and the ownership of both native windows before acting.
For that separate observer, use `measure.ps1 -SystemOnly` through the diagnostic
transport; this never launches or controls a desktop application. Both streams
include the machine's monotonic QPC ticks/frequency for alignment. Guest wall
clock configuration must be recorded separately. The CSV streams each observation
batch so a failed long run retains diagnostic data. An existing output is rejected.
The collector includes ExplorerPatcher's optional DWM helper when present.
Benchmarks also record fixture and harness processes separately as test overhead.
Use `benchmark.ps1 -IncludeGpu` (or `measure.ps1 -IncludeGpu`) for the next series
on this VM, where GPU counters are available. The test-only PDH reader reuses
one query and native buffer, writing `<process.csv>.gpu.jsonl` with QPC bounds,
per-engine utilization and per-process dedicated/shared graphics bytes. Only
the CPU observer's process scope and provider-error records are retained.
Unavailable values remain null; rate counters need two samples, so an initial
engine observation can be unavailable. Interpret subsequent interval rates
separately from the initial point. See Microsoft's
[PDH array documentation](https://learn.microsoft.com/en-us/windows/win32/api/pdh/nf-pdh-pdhgetformattedcounterarrayw).
Keep engine instances separate. Per-process graphics-memory values include
cross-process sharing and must not be summed as a unique physical footprint or
added to private commit; see Microsoft's
[GPU memory accounting explanation](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).
`python Tests/dynamic/summarize_gpu.py <phase.csv>` validates each GPU record
against its CPU batch, process scope, commit and QPC interval. It reports valid,
absent and invalid observations separately for each engine/adapter instance,
including roles with no reported counter instances. It preserves provider
errors and summarizes collector read time. Medians use valid observations only;
check their coverage before interpreting them. `compare.py` includes these
absolute GPU summaries for every phase when GPU collection was enabled, and
rejects mixed instrumentation. It does not sum GPU engines or process memory.

These are the guest's counters, not physical-GPU power measurements. The aborted
first series used its original CPU/RAM collector throughout; no GPU results are
retroactively attributed to it.
Candidate phases also use `-RequireDynamic`: the collector saves the first
stopped/paused observation and fails immediately, instead of continuing a known
invalid five-minute interval. The baseline does not require Dynamic.
On failure it also writes `<csv>.sampler-failure.json`, querying scheduler context
once when supported. Valid full resource intervals keep their ordinary query
count; detailed periodic queries still require `-IncludeScheduler`.
`summarize.py` reports per-process absolute metrics and rates, preserves missing
values and refuses short/SMOKE data as benchmarks. Its optional DWM stream
interpolates cumulative CPU at common QPC endpoints only when the observer
brackets them with gaps of at most six seconds.
`compare.py <suite-directory> --dwm-observer <observer.csv>` requires a complete
fifteen-phase suite, fixed real geometry/DPI matching its label, full measured
durations and QPC-verified warmups, and the alternating three-repeat order.
Receipts must match the pinned build manifest and successful target exit. Both
candidates must use one application revision, with unchanged fixture hash/nominal
intervals throughout the suite. Candidate rows are rechecked for active sampling,
progress, capture errors and the static reference color, even when a status file
says complete. The elevated DWM stream must match the actual process identity
and clock frequency at its interpolation endpoints. It subtracts the arithmetic mean of
the adjacent baselines from each candidate, preserves negative differences and
reports repetition values, medians and ranges. Combined CPU includes the app,
Explorer, DWM and the optional taskbar helper; observer and workload costs stay
separate. Missing CPU remains unknown. Private-memory median differences are
reported for the app and each affected process, plus their combined private
commit; this does not sum shared working sets or measure GPU allocations.
Bracketing estimates incremental cost; it
does not establish causation or a statistical confidence interval.
The output includes all fifteen absolute phase summaries and build receipts.
Inspect these trajectories for memory retained after a candidate closes:
adjacent-baseline subtraction does not remove that carryover.

The worker accepts the registered read-only message `TTB_QueryDynamicStats`.
Its wParam selects samples attempted (0), confirmed color changes (1), actual
Dynamic appearance applications including event restorations (2), last confirmed
RGB packed as 0xRRGGBB (3), latest winning run length (4), timer active (5),
session/display paused (6), or latest sample GetTickCount64 value (7). Field 255
returns the protocol marker 0x44594E01. Match both the worker class and its
`TTB_WorkerWindow` caption; an empty string caption does not match it. No log is
written in the normal capture path. An application count may exceed a color
change count because real Explorer events require restoration.
Field 254 is a capability mask: bit 0 enables completed capture frames (8),
DXGI wait timeouts (9) and capture failures (10). These cumulative counters
survive resource resets. A timeout may reuse a cached result and is not a new
captured frame. The collector distinguishes attempts from completed frames and
leaves extended fields empty for older revisions.

Capability bit 1 enables bounded scheduler diagnostics. `measure.ps1
-IncludeScheduler` opts into those extra queries for diagnostic sessions;
ordinary resource suites do not query them. The application retains scalar
snapshots and counters, with no continuous file logging or new polling thread.

| Field | Scheduler diagnostic |
| --- | --- |
| 11 / 12 | Current context flags / taskbar-map size |
| 13 / 14 | Context at entry to the last stopping update / immediately before stopping |
| 15 / 16 | Last stop GetTickCount64 / taskbar-map size at that stop |
| 17 / 19 | Desktop appearance at last stop / current Desktop appearance |
| 18 | Last regular-timer creation error |
| 20 / 21 | Regular-timer stop count / timer creation failure count |

Context bits are locked=1, display-off=2, attribute replies suppressed=4,
state reset in progress=8, sampling in progress=16, empty taskbar map=32 and
Desktop configured with another appearance=64; application shutdown=128. These are context, not a list of
independent stop reasons: another state can legitimately select Dynamic while
Desktop uses Clear. Appearance values are Normal=0, Opaque=1, Clear=2, Blur=3,
Acrylic=4 and Dynamic=5. A zero last-error value does not override a nonzero
timer creation failure count. Instrumentation revision51b47c3 did not change
timer policy. A subsequent controlled probe showed64transient stops in6seconds
when a synthetic unlock notification recalculated policy while composition
refresh replies were suppressed. Current source keeps the timer/capture alive
during that temporary suppression and uses a separate shutdown flag; sampling
still skips the critical section. Actual lock, display-off and inactive
appearances retain their stop behavior. This removes the demonstrated transient
teardown path; the spontaneous long-series stop still needs validation.

`refresh-race.ps1 -PolicyRecompute` covers that overlap through the actual worker
message handler. It sends a synthetic WTS unlock notification while beginning
already unlocked; it never locks/unlocks the real session and does not establish
session-lock compatibility. The positive regression requires no additional
regular-timer stops. `-ExpectTransientStops` is only for the known-broken negative
control, which finishes active but records the unwanted stops.

For XAML taskbars, Dynamic also requests the light/dark theme with greater
black/white contrast on that taskbar's XAML root. The chosen RGB is unchanged.
The original local theme is restored on mode changes, exit and process death.
This behavior still requires visual validation on each taskbar implementation;
classic-taskbar contrast is not yet implemented. The fork uses a distinct TAP
protocol version so it cannot accidentally reuse a stock appearance service.
