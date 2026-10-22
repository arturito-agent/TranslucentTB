# Chameleon appearances

## Selecting a mode

**Chameleon (continuous)** remains available in every appearance submenu. It
captures approximately every 500 ms while effective, with a coalesced early read
on activation/foreground change. It follows stable content changes without
requiring the application to emit an event.

**Chameleon (trigger based)** is available only in Maximized window, including
its application rules. Existing state/rule precedence applies. The sampler uses
the highest maximized window in each monitor's z-order as the responsible HWND.
Changing that HWND, activating the mode, or changing monitor/taskbar geometry
requests a deferred read. Returning from lock/display-off or rebuilding Explorer
state invalidates the context and samples again.

The trigger variant adds no WinEvent subscriptions, content hooks or helper
process. Existing foreground, window-state and z-order callbacks resolve the
context. An unchanged HWND and geometry returns without scheduling capture.
Titles can still affect upstream application rules, but do not themselves request
samples when the effective context stays unchanged.

## Bounded work

Only one shared deferred capture timer can be pending. Context replacements use
the latest state without extending its deadline; duplicate events cannot add
reads. The first read runs after about 500 ms, allowing the maximize animation to settle. An unchanged RGB stops immediately;
a new candidate gets at most one confirmation at least 200 ms later. If the two
samples disagree, the old accepted color remains until another context change.
Every attempt, including foreground changes, shares the same 200 ms minimum.
No capture timer remains after the work is consumed. The continuous mode can
still run its own 500 ms timer on another monitor.

This is deliberately narrower than the retired v2 content-event burst scheduler.
Changing titles, selecting a tab, scrolling, video and silent paints can change
pixels without changing the context. Trigger based may retain an outdated color
until the next supported event. Choose continuous when content following matters.
Fewer captures alone do not establish lower CPU during arbitrary application use.

## Shared color and animation

Both capture one physical pixel immediately outside the actual bottom, left or
right taskbar, with zero gap and the full monitor edge length. Four-level RGB
buckets find the longest continuous similar-color run; its exact midpoint source
pixel supplies the output, without averaging. Candidates need two observations
at least 200 ms apart. Identical confirmed targets do not reapply or restart an
animation, apart from necessary Explorer appearance recovery.

Both retain 240 ms transitions: independent XAML brush animation on modern bars,
bounded 33 ms animation timer on classic/lateral bars. Animation frames never
capture the screen, and disabled Windows UI animations are respected. Capture
resources and timers stop while inactive, locked, display-off or exiting.

## Configuration and diagnostics

The canonical values are `chameleon` (numeric 5) and `chameleon_triggered`
(numeric 6). Legacy `dynamic` maps to continuous and `dynamic_v2` to trigger based.
Fallback colors and enable flags survive migration. Trigger based settings in
other states resolve to the configured opaque fallback, without pixel capture.

The existing read-only `TTB_QueryDynamicStats` message has no disk writer. Field 5
reports the continuous timer; 27 the deferred timer; 28 remaining trigger reads;
29 changed active contexts; 33 context checks and 34 unchanged contexts. Context
checks include ordinary upstream refreshes, not just external WinEvents. Existing
capture, accepted-color, application and animation counters remain available.

## Validation and limits

Portable checks exercise duplicate bursts, one-read equality, bounded confirmation,
supersession and cancellation alongside shared geometry/color/animation checks.
Native configuration tests cover both canonical and legacy values and WinRT.
`Tests/dynamic/events-check.ps1` compares short idle/noisy-event observations,
checks silent-paint differences, real maximized HWND switches, same-RGB dedup,
physical transition colors, deactivation and bottom/left/right positions.

Native `ed7ad98` passed 84 native tests and 2,042 portable checks in
[Windows CI](https://github.com/arturito-agent/TranslucentTB/actions/runs/39811657138).
The actual VM run passed both modes on classic Bottom/Left/Right, active moves
Bottom → Left → Right → Bottom, and the trigger variant on the modern taskbar.
Exact physical colors, one-level RGB changes, intermediate animation colors,
silent-paint differences, noisy-event filtering and inactive capture suspension
passed. Modern continuous behavior also passed on `b1cc217`, whose continuous
implementation is unchanged by the later trigger-delay fix.

Across each five-second classic idle interval, continuous captured 10 frames;
trigger based captured zero. Across three approximately 3.5-second noisy-event
intervals, trigger based filtered all 840 unchanged context checks and captured
zero frames; continuous captured 21. New-RGB HWND switches took two trigger reads.
Same-RGB switches on Bottom/Right took one read and no application; the Left
case retained its context and required none. Active taskbar moves updated the
color with the same responsible window. The modern trigger run likewise had
zero idle/noisy captures and no timers left running after work.

Both used approximately 9.3–9.5 MiB private commit and 52–55 MiB working set.
Application idle CPU was about 0–0.3% of one logical core; noisy-event intervals
were about 0.4–1.3% in both modes. Five-second boundaries and process CPU timer
resolution make these rough figures. They do not demonstrate a consistent CPU
advantage for the trigger variant. The demonstrated benefit is fewer captures;
continuous remains preferable for following silent content changes.

[Sanitized observations and summaries](dynamic-results/chameleon-events-ed7ad98.json)
pin the actual executable and helper hashes. The helper waits for a discovered
bar and sends a benign WM_NULL to let Explorer's injection hook initialize before
timed phases. Early startup attempts that timed out in XAML Diagnostics or began
before discovery were excluded; they are not successful recovery evidence.
The 200 ms initial trigger read also missed an unfinished maximize frame in the
first build; the tested final version defers that read to 500 ms, then confirms
at least 200 ms later. No periodic timer was added to work around those failures.
Historical resource figures remain versioned in the earlier reports. Classic
glyph contrast on dark backgrounds is unresolved; HDR, multiple monitors and all
DPI combinations are not established. No security setting or extra privilege is
required, and captured pixels are not sent to disk or a network by this feature.
