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

Each relevant event group requests up to three confirmation reads, starting
after about 200 ms and continuing about 300 and 500 ms apart. Repeated events
share the pending burst; an event during a burst refreshes its bounded remaining
reads without delaying its first deadline. Once events stop, the burst drains
and its timer is killed. There is no permanent 500 ms timer for v2. Deactivation,
screen-off/session-lock and shutdown cancel pending work. Original v1 retains
its existing periodic behavior when selected.

These are native WinEvents, not a universal browser integration or a full UI
Automation tree observer. Applications may omit scroll/selection notifications.
Automatic page changes, delayed loads and video frames can therefore leave the
previous color until another supported event. Classic-taskbar glyph contrast
retains the documented limitation on dark backgrounds.

## Validation and measurements

Windows build, actual VM functional checks, a brief approximate consumption
observation, and final extracted-package verification are pending. Existing
v1 resource figures do not measure v2. No long benchmark matrix is required.
