# Chameleon appearance

Chameleon is the single adaptive appearance in this fork. It replaces the old
Dynamic name and retains periodic capture. Dynamic v2's event-only scheduler,
content hooks and menu option have been removed. This is a product simplification,
not a new resource benchmark.

## Behavior

Choose Chameleon alongside Normal, Opaque, Clear, Blur and Acrylic in any existing
appearance submenu, including Desktop and Maximized window. The existing state
and application-rule precedence is unchanged.

While effective, Chameleon captures approximately every 500 ms. A foreground
change or activation can request a coalesced deferred read; all attempts share a
200 ms minimum. It therefore observes stable silent page paints without requiring
an application to emit an accessibility event. Capture resources and timers stop
when no taskbar needs Chameleon, the display turns off, the session locks or the
application exits.

Sampling reads a one-physical-pixel line immediately outside the actual bottom,
left or right taskbar, without a gap. It spans the full monitor edge and selects
the longest continuous similar-color run. RGB buckets only identify that region;
the output is the exact middle source pixel, never a channel average. Thin borders
and shadows directly adjoining the taskbar are intentionally eligible. A candidate
must repeat after at least 200 ms. Identical targets do not reapply or restart
animations, except for necessary shell appearance recovery.

Transitions retain the tested 240 ms implementation: independent XAML brush
animation on the modern taskbar and a bounded 33 ms timer on classic/side taskbars.
No transition frame recaptures the screen. The endpoint is exact and Windows'
disabled UI animations are respected. See [the implementation report](dynamic-exact-transitions.md).

## Existing settings

The canonical JSON value is `"accent": "chameleon"`. Old `dynamic` and `dynamic_v2`
values deserialize to Chameleon and are saved as `chameleon`. This applies to
ordinary states, per-window rules and inactive appearances through the shared
appearance parser. Fallback color and other appearance fields are preserved.
The legacy v2 name is an input alias only, with no event-driven runtime behind it.
Its Maximized window enabled flag keeps its existing value.

Chameleon retains numeric appearance value 5 internally. The read-only diagnostic
message retains its old name for existing tools; capability bit 3 (v2) is cleared,
and removed event fields return zero. No permanent diagnostic writer is added.

## Validation and limits

The existing native configuration tests cover canonical and legacy JSON values,
WinRT conversion and canonical serialization. Portable checks cover adjacent-edge
geometry, exact color, stability, deduplication and transitions. Obsolete burst
scheduler checks and the v2-only live helper have been removed. Current Windows
build provenance is supplied with each release's BUILD.json.

Earlier CPU/RAM figures and interactive VM observations remain historical and
versioned in the comparison reports. No new CPU/RAM campaign is required for this
rename/removal. Classic glyph contrast on some dark colors remains unresolved;
multiple monitors, HDR and all scaling combinations are not established.

Native source `aeed2fd730b31a680a4d81858dce0a2834516563` passed **84 native tests**
and **2,034 portable checks** in [Windows CI](https://github.com/arturito-agent/TranslucentTB/actions/runs/39794919939).
The native migration test covers `chameleon`, `dynamic` and `dynamic_v2`, WinRT
conversion, canonical `chameleon` serialization and retained fallback colors.
Static menu verification found exactly seven Chameleon entries and no v2 entry.
The retired burst scheduler's nine checks are no longer part of the portable
suite. No resource measurements or interactive VM session were repeated.
