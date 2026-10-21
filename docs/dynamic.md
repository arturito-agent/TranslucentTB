# Dynamic appearance (experimental)

Dynamic is a native appearance option alongside Normal, Opaque, Clear, Blur and
Acrylic. Select it separately for Desktop, Visible window, Maximized window,
Start opened, Search opened, Task View opened or Battery saver. Existing
appearance selection and application rules determine which monitor needs it.
In JSON, set `"accent": "dynamic"` on any supported appearance or rule.

This is an experiment in progress. The native menu, bottom-taskbar color,
configuration persistence and exit restoration were exercised on Windows 11
26100.8875 with revision 3ea6890. Full integration coverage, benchmarks and lateral
taskbar compatibility remain pending. No performance result is claimed.

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
the prior output. The initial scheduler samples every 500 ms with timer
coalescing. Existing window events group appearance refreshes; they do not
perform pixel captures. Sampling only applies changed colors. Explorer
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

The collector includes a final endpoint, checks an optional target PID, keeps
the observer's costs separate, and leaves unavailable metrics empty with an
error reason instead of omitting the process or reporting zero. Protected DWM
CPU counters may need a separate elevated read-only observer. The instance can
be queried or closed gracefully with `session.ps1`, which checks its executable
path and the ownership of both native windows before acting.

The worker accepts the registered read-only message `TTB_QueryDynamicStats`.
Its wParam selects samples attempted (0), confirmed color changes (1), actual
Dynamic appearance applications including event restorations (2), last confirmed
RGB packed as 0xRRGGBB (3), latest winning run length (4), timer active (5),
session/display paused (6), or latest sample GetTickCount64 value (7). Field 255
returns the protocol marker 0x44594E01. Match both the worker class and its
`TTB_WorkerWindow` caption; an empty string caption does not match it. No log is
written in the normal capture path. An application count may exceed a color
change count because real Explorer events require restoration.

For XAML taskbars, Dynamic also requests the light/dark theme with greater
black/white contrast on that taskbar's XAML root. The chosen RGB is unchanged.
The original local theme is restored on mode changes, exit and process death.
This behavior still requires visual validation on each taskbar implementation;
classic-taskbar contrast is not yet implemented. The fork uses a distinct TAP
protocol version so it cannot accidentally reuse a stock appearance service.
