# Dynamic v2: event-driven maximized appearance

Dynamic v2 is available only under **Maximized window → Enabled → Dynamic v2**.
The original Dynamic option remains available for comparison. JSON uses
`"accent": "dynamic_v2"` in `maximized_window_appearance`. Elsewhere, an invalid
v2 selection resolves to an opaque fallback rather than starting capture.

The selected backend is GDI. Color/geometry analysis is shared with Dynamic v1:
a four-physical-pixel strip, two pixels outside the bottom/left/right taskbar,
and the longest continuous similar-color run. The chosen RGB remains unchanged.

## Triggers and idle behavior

- Entering the maximized appearance or changing foreground window.
- Relevant window location/size/title changes, including maximize/restore.
- Native accessibility selection and scroll-completed events, when the app emits them.
- Taskbar/display geometry changes, Explorer recovery, and session/display resume.

Each accepted event requests a fixed three-read burst, normally starting after
about 200 ms and continuing about 300 and 500 ms apart. Notifications during a
burst do not replenish its reads. Ordinary content first-read deadlines are
spaced by at least two seconds; an event during cooldown queues the next bounded
burst. Real foreground changes and v2 activation bypass this cooldown. Unchanged
titles/rectangles and repeated selection identifiers are filtered, and taskbar
notifications are excluded. Extra content hooks are registered only while v2 is
effective. Once the burst drains its timer is killed. There is no permanent
500 ms capture timer for v2. Deactivation, screen-off/session-lock and shutdown
cancel pending capture work. Original v1 retains its periodic capture behavior.

Both modes now use exact source-pixel RGB and bounded transitions; see
[the current update and comparison](dynamic-exact-transitions.md). These changes
postdate the v0.2.0 validation below.

These are native WinEvents, not a universal browser integration or a full UI
Automation tree observer. Applications may omit scroll/selection notifications.
Automatic page changes, delayed loads and video frames can therefore leave the
previous color until another supported event. Classic-taskbar glyph contrast
retains the documented limitation on dark backgrounds.

## Historical v0.2.0 validation and measurements

Native source `fb366959d63be64612b0de7f47ae0851c79c15e3`, GDI, passed
84 native tests and 2,029 portable checks in [Windows CI](https://github.com/arturito-agent/TranslucentTB/actions/runs/39641419159).
The executable SHA-256 is
`26e9b09e8168d555832fb1f9fecd0fa95fb6b62b4e3b09989aeb4203f8d4b6da`.

A single real Windows process followed Bottom → Left → Right on Windows 11
26100.8875 with ExplorerPatcher 26100.8457.70.3, 2 vCPUs, 6 GiB RAM, Basic Display
Adapter and a 1280×800 SDR display at 100% scaling. Each position passed:

- True maximized-window activation and exact physical taskbar colors `#F8F8F8`
  and `#101010` before/after a native title-change event.
- Capture counters unchanged during idle (30 seconds bottom, 5 seconds each side),
  both periodic/burst timers off and zero pending reads.
- A silent paint retained the old color; the next title event updated it and
  drained its three-read burst.
- Restoring the window stopped capture; the application exited gracefully.

A separate six-event sequence over about 18 seconds completed 18 captures and
returned to idle. Approximate **application-only** consumption from this brief run:

| Observation | CPU, one logical core | Private commit | Working set |
| --- | ---: | ---: | ---: |
| Bottom idle, 30 s | below process-time resolution | 9.3 MiB | 49 MiB |
| Six events, 18 s | about 0.09% | 9.3 MiB | 47 MiB |
| Side idle, 5 s each | about 0–0.3% | 9.2–9.3 MiB | 43–46 MiB |

The active sequence is about 0.04% of this two-vCPU VM's total CPU capacity.
The short side intervals are noisy: one 15.6 ms process-time tick gives about
0.3% of one core. Zero recorded CPU does not mean literally zero instructions;
zero capture is established independently by the counters. Working set includes
resident shared framework pages, so private commit alone is not total RAM.
Explorer/DWM/GPU were not remeasured for v2. These are approximations from one
VM, not universal performance guarantees or the older v1 comparison.

[Raw synthetic observations](dynamic-results/v2-fb36695.json) preserve timings,
CPU, memory and capture counters. Reproduce the scoped check using
`Tests/dynamic/v2-check.ps1` with a fresh output directory and the reviewed
ExplorerPatcher version. No long benchmark matrix is required.

The [v0.2.0 distribution](https://github.com/arturito-agent/TranslucentTB/releases/tag/dynamic-v2-v0.2.0)
passed separate Windows extraction (107 file checksums), launch, UI menu
selection, settings persistence through tray Exit, restart, a maximized light
reference and final tray Exit. The exact ZIP was downloaded anonymously after
publication and its SHA-256 matched:
`98847b0d6e7e85b4396960652037e560a73952b82dd9cf1e8ca63739c65552c6`.
Its bundled documentation is pinned to `3e60e61`; this publication receipt
updates the repository documentation without changing that tested ZIP.
Native scroll/selection hooks are implemented; the live color-update checks
above specifically exercised title events and maximize/restore. Browser/provider
coverage, multiple monitors and HDR were not established by this run.
