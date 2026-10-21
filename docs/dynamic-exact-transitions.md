# Exact color, bounded transitions and capture strategy

This update keeps the existing Dynamic (periodic) and Dynamic v2 (event-driven,
Maximized window only) menu entries. This report distinguishes the current exact-color validation from historical
v0.2.0 measurements.

## Adjacent edge update (v0.3.1)

Both modes now capture a one-physical-pixel line immediately adjacent to the
actual taskbar with zero gap. The line spans the monitor's full width (bottom)
or height (left/right); only its thickness changes. A document preview can have
a thin dark border beside white content. The previous four-pixel strip with a
two-pixel gap could choose that interior white instead of continuing the border.
The new line reads the border itself. No cross-strip voting or averaging is
needed; the longest continuous run, exact midpoint RGB, temporal confirmation,
deduplication, schedules and transitions remain as before. Following a thin
shadow or border is intentional. The validation and resource figures below
refer to v0.3.0; this geometry adjustment does not establish new CPU/RAM numbers.

## Exact source color (v0.3.0)

Four-level RGB groups are used only to find the longest continuous similar-color
region. Each cross-strip representative is a real winning pixel; the region's
final RGB comes from its middle representative. Neither step averages channels.
Temporal confirmation compares exact RGB, and an already-applied exact target
is skipped. This includes one-channel changes inside the same grouping bucket.

The initial color remains opaque. After a transition, the final value is the
exact selected RGB. Intermediate transition colors are intentionally interpolated.
Explicit shell appearance invalidations may require reapplying the current
color; ordinary title/geometry refreshes must not restart an identical target.

## Short transitions

The modern XAML taskbar retains a SolidColorBrush and animates its Color with a
240 ms ColorAnimation, without enabling dependent animation. Windows handles
intermediate frames through its independent animation machinery. See
[Microsoft's animation performance guidance](https://learn.microsoft.com/en-us/windows/apps/develop/performance/optimize-animations-and-media).

The classic/lateral taskbar has a bounded 33 ms timer for approximately 240 ms,
interpolating only the known source and target colors. Its timer is killed when
the transition ends, is cancelled, or Dynamic becomes inactive. No intermediate
frame captures the screen. A new target starts from the current displayed color
instead of queueing obsolete transitions. Disabled Windows UI animations select
the target immediately.

## Event filtering

V2 only registers its extra native content hooks while it is effective. It
rejects taskbar-originated events, unchanged titles, unchanged window rectangles,
and duplicate selection identifiers. Ordinary content events cannot extend a
running three-read burst. Their first-read deadlines are spaced by at least two
seconds; a new content event during cooldown queues a bounded burst instead of
being discarded. Real foreground changes and entry into v2 bypass that cooldown.

These events are notifications emitted by Windows/apps, not proof that the
sampled edge changed. Provider coverage still matters. Silent page/video updates
may leave v2 with the previous color; periodic Dynamic can observe those updates
when they produce a stable eligible region.

## Brief validation method

`Tests/dynamic/exact-compare.ps1` exercises each mode.
It records process CPU time/QPC, private/working memory, Explorer CPU time and
capture/target/write/event counters. Scenarios include idle, duplicate native
name/location notifications, a one-level exact RGB change, physical intermediate
transition pixels, repeated real title changes, silent content and deactivation.
`-WithBrowser` adds an owned offline Edge app/profile with title-triggered and
silent paints. `-SidesOnly` checks bottom, left and right on the reviewed classic
ExplorerPatcher implementation. Only synthetic observation/pixel data is suitable
for publication; browser profiles and private operational logs are excluded.

This is an approximate comparison without repeated benchmark matrices or a claim
about all applications. DWM/GPU costs are not inferred from application CPU alone.
The recommendation must consider missed changes as well as captures saved.

## Current Windows findings

Native source `773bc58933df16f3719a29412fb08c3a83bf6bd5` passed 84 native tests
and 2,041 portable checks in [Windows CI](https://github.com/arturito-agent/TranslucentTB/actions/runs/39676271645).
Periodic observations use `7ccc0f34e5a6dfbe8fcf045d42503a765eb2452a`, which passed
the same checks. The only native change between these revisions moves allocation
of the v2 callback before its executable thunk page is sealed. The capture,
analysis and transition implementations are unchanged; both Explorer DLLs have
identical SHA-256 values. These are sequential approximate observations, not a
controlled statistical comparison of identical executable files.

Environment: offline Windows 11 LTSC 26100.8875, two vCPUs, 6 GiB RAM, Microsoft
Basic Display Adapter, one 1280×800 SDR display at 100%, modern XAML bottom bar.
Both modes passed native maximized reference colors #F9F6F3, one-level #FAF6F3
inside the same bucket, and #436E99. Physical intermediate pixels were observed
and the settled taskbar matched the exact target. Neither reapplied identical
targets during idle or duplicate events. Restoring the window stopped capture
and animation. The v1 pixel assertions passed before the combined controller
later hit the callback defect when activating v2; its raw transition array was
not saved. V2 has a saved physical pixel trace.

| Brief scenario | Periodic v1 captures / CPU | Event v2 captures / CPU |
| --- | ---: | ---: |
| Idle, about 15 s | 29 / 0.10% | 0 / below process-time resolution |
| Duplicate title/rectangle notifications, about 10 s | 20 / 1.40% | 0 / 0.31% |
| Changing titles, about 11 s including settling | 22 / 0.14% | 15 / 0.28% |

CPU percentages refer to one logical core and the application only. The
synthetic duplicate case emits about 40 notifications per second and includes
upstream window-state handling. The short changing-title intervals do not prove
v2 has lower CPU: fewer captures are not automatically less total event work.
Private commit was about 9.3–9.4 MiB for either mode; observed working set was
about 48–54 MiB. One 15.6 ms process-time tick over 15 s is about 0.1%; zero is
below this observation's resolution, not literally no instructions. Explorer
CPU is preserved in the raw observations; it includes the title/browser workload
and is not isolated Dynamic overhead. No DWM/GPU measurement was made here.

A silent native repaint to #E8DDD1 was detected by v1. V2 retained #436E99 with
zero captures until the next title event, then converged to #E8DDD1. During Edge
loading, v2 sampled its initial #F3F3F3 surface and missed the later #F9F6F3 page
paint. This demonstrates a real coverage tradeoff rather than an RGB rounding
error. The separate Edge check confirmed exact physical #436E99 after its
title event, retained that color during the silent #E8DDD1 paint without another
capture, and reached exact #E8DDD1 after the next title event, then exited normally.

[Periodic observations](dynamic-results/exact-periodic-7ccc0f3.json) and
[event observations and physical transition trace](dynamic-results/exact-events-773bc58.json)
contain synthetic counters only; no browser profiles or personal records.

The same new binary retained one process through real classic taskbars Bottom →
Left → Right using ExplorerPatcher 26100.8457.70.3. Each position passed the
three exact reference colors, physical intermediate transition colors, no idle
captures or identical writes, stopped animation timers, and inactive capture
suspension. A one-level color change required one classic write; the larger blue
transition required five observed writes in this VM. It did not recapture per
animation frame. The target exited normally. See
[side observations and physical pixels](dynamic-results/exact-sides-773bc58.json).
Classic glyph contrast on dark backgrounds remains unresolved; this check does
not establish HDR, multiple displays, or all scaling combinations.

## Recommendation

Keep periodic **Dynamic** as the general recommendation when the bar should
follow the visible content, including silent browser updates. Its idle capture
cost in this VM was already small. Offer **Dynamic v2** only in Maximized window
for users who prefer capture suspension at rest and accept that unsupported
paints can retain an old color. Do not replace v1 universally or claim events
always save CPU. Both modes deduplicate exact targets; animations run only
when a different color is accepted.

Keep v2's foreground/root filters, unchanged-title/rectangle filters, fixed
three-read bursts, two-second ordinary-content cooldown, and inactive hook/timer
cleanup. Do not add a permanent fallback timer and still describe it as a purely
event-driven mode. A universal content-change detector would need a separate
cost/coverage decision; it is outside this release.

## Published package

[v0.3.0 experimental release](https://github.com/arturito-agent/TranslucentTB/releases/tag/dynamic-v0.3.0)
contains the tested x64 GDI runtime and documentation pinned to
`c0e4178e218ecbe7c9ec516cf2b349f2649c0412`. The final ZIP was extracted in Windows,
all 111 manifest entries matched, and its first launch contained no settings.
Welcome/Continue, Maximized window Enabled and Dynamic v2 selection through the
actual menu passed. Tray Exit saved those settings; restart retained them and
a maximized reference produced physical and internal #F9F6F3 with both capture
and animation timers stopped after settling. The owned application exited normally.

The published ZIP was downloaded without authentication and matched the exact
Windows-tested archive. SHA-256:
`cd5dbae6ca7d4e5212a2fa84f87fc9ebd1d8a7a9d91aab4e721b9b85be34310a`.
This receipt updates the repository report; it does not rebuild that ZIP.
