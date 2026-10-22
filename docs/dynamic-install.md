# Run TranslucentTB Chameleon

This is Arturito's experimental TranslucentTB fork. The executable is an
unsigned x64 development build; its tray caption includes `(Dev)`. Download
the ZIP attached to this fork's release and extract the entire folder to a
writable location. Keep the DLLs and resources beside `TranslucentTB.exe`.
Do not run the application directly inside the ZIP or alongside another
TranslucentTB instance.

## Requirements

- Windows 11 x64. The tested environment and resource measurements are listed
  in [the validation report](dynamic-validation.md).
- The Microsoft Visual C++ v14 x64 runtime, at least as recent as the compiler
  recorded by the build. The current tested build uses runtime 14.51.36247.
  Use [Microsoft's runtime downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/).
- The Microsoft.UI.Xaml 2.8 and VCLibs framework packages declared by the
  application's manifest. See [the upstream build instructions](../CONTRIBUTING.md)
  when preparing a machine that does not already have these dependencies.
- For lateral taskbars in the tested Windows 11 configuration, ExplorerPatcher
  26100.8457.70.3 using its Windows 10 taskbar implementation. Obtain it from
  [its official repository](https://github.com/valinet/ExplorerPatcher/releases).
  This fork does not install or bundle ExplorerPatcher.

## Enable Chameleon

1. Exit the old TranslucentTB instance, then extract the complete new ZIP.
2. Run `TranslucentTB.exe` as the ordinary desktop user.
3. Choose **Chameleon (continuous)** in any appearance submenu, or enable
   **Maximized window → Chameleon (trigger based)**.
4. Other enabled states and application rules keep their normal precedence.
5. Fallback color sets the initial opaque color until a stable sample is confirmed.

Continuous samples approximately every 500 ms and follows stable silent paints.
Trigger based samples after changes of the responsible maximized window or
monitor/taskbar geometry. Titles, scrolling and silent paints alone do not trigger
it, so a page can change without updating the bar until the next context change.
Both modes stop capturing while inactive, locked or display-off.

Existing `dynamic` settings load as continuous; `dynamic_v2` loads as trigger based.
Saves use `chameleon` and `chameleon_triggered` respectively. Trigger based values
outside Maximized window use their configured opaque fallback. Copy an existing
settings.json into the new portable folder to retain configuration.

Sampling uses one physical pixel immediately next to the actual bottom, left or
right taskbar, with no gap. Exact RGB selection and 240 ms transitions are kept.
See [Chameleon behavior](chameleon.md). Top taskbars remain outside this experiment.

When upgrading, exit the old build first. If the upstream development build
requests a Windows restart because Explorer holds an older DLL, restart Windows
and launch the new folder once.

## Settings and exit

In the portable build, `settings.json` lives beside the executable and is saved
through the existing application settings mechanism. Retain your own copy
before replacing a previous portable installation. Extracting a new build into
a separate folder keeps its portable settings separate.

Select another appearance to stop using Chameleon for that state. Choose **Exit**
to close the application and restore the taskbar appearance managed by the
existing TranslucentTB exit path. This experimental ZIP does not require an
installer or changes to Windows security settings.

## Known limits

Classic taskbar glyphs follow the system theme and can have poor contrast on
some Chameleon backgrounds; the modern XAML taskbar adapts its glyph theme. Color
tests do not establish readability. See the validation report for recovery,
display, scaling and other tested or unavailable combinations.

GDI is selected using the existing approximate [resource comparison](dynamic-resources.md).
Download the **Chameleon** release asset from this fork's [releases](https://github.com/arturito-agent/TranslucentTB/releases).
Its `BUILD.json` pins the native source and bundled documentation; `SHA256SUMS`
verifies each included file. See [Chameleon behavior and migration](chameleon.md).
