# Dynamic appearance (experimental)

Dynamic is a native appearance option alongside Normal, Opaque, Clear, Blur and
Acrylic. Select it separately for Desktop, Visible window, Maximized window,
Start opened, Search opened, Task View opened or Battery saver. Existing
appearance selection and application rules determine which monitor needs it.
In JSON, set `"accent": "dynamic"` on any supported appearance or rule.

This is an experiment in progress. Windows integration, benchmarks and lateral
taskbar compatibility are not yet verified. No performance result is claimed.

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

Use the upstream [build instructions](../CONTRIBUTING.md), Release x64. The
`Dynamic Windows build` workflow builds the pinned upstream baseline and this
branch with the same runner family and configuration, then uploads test output
and Windows artifacts. It does not sign or publish installers. Runner/image and
dependency revisions must be retained with measurements.

The platform-independent geometry, run-selection and stability tests also run
without Windows or third-party dependencies:

```sh
g++ -std=c++20 -O2 -Wall -Wextra -Werror -pedantic -I Common \
  Tests/dynamic/standalone.cpp -o dynamic-tests
./dynamic-tests
```

Configuration/WinRT round-trip tests run in the existing Windows test suite.
The final experiment report will record actual Windows behavior, compatibility,
resource use, capture-backend comparison and remaining limitations.
