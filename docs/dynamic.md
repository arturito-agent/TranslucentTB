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
taskbars. The fixture uses physical-pixel DPI awareness and keeps its display on
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
Lateral runs use `taskbar-position.ps1` with the reviewed ExplorerPatcher
26100.8457.70.3 private position message. The driver checks its version/module,
reapplies the real edge after each Explorer restart and refits the owned fixture.
Every CSV batch records physical taskbar bounds, edge and DPI. A phase with a
different edge, paused/stopped sampling, failed captures or incorrect static
reference color is rejected. `states.ps1` checks the documented state/rule
configurations, including fallback use on unreliable native window frames.

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
`summarize.py` reports per-process absolute metrics and rates, preserves missing
values and refuses short/SMOKE data as benchmarks. Its optional DWM stream
interpolates cumulative CPU at common QPC endpoints only when the observer
brackets them with gaps of at most six seconds.

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

For XAML taskbars, Dynamic also requests the light/dark theme with greater
black/white contrast on that taskbar's XAML root. The chosen RGB is unchanged.
The original local theme is restored on mode changes, exit and process death.
This behavior still requires visual validation on each taskbar implementation;
classic-taskbar contrast is not yet implemented. The fork uses a distinct TAP
protocol version so it cannot accidentally reuse a stock appearance service.
