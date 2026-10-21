# Run the Dynamic experiment

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

## Choose a capture strategy

For content-following behavior, use **Dynamic**: its periodic capture also sees
silent page paints. Use **Dynamic v2** under Maximized window to stop captures
at rest, accepting missed silent updates. Both now use exact source RGB and
short color transitions. See [the comparison](dynamic-exact-transitions.md).

## Enable Dynamic v2

1. Exit any other TranslucentTB instance from its tray menu.
2. Run `TranslucentTB.exe` as the ordinary desktop user.
3. Open its tray menu, select **Maximized window → Enabled**, and choose
   **Dynamic v2** in that same submenu. It is available only in this state.
4. Keep **Desktop** on a fixed appearance such as Clear. Other enabled states
   (Start, Search, Task View, Battery saver) retain their normal precedence.
5. Maximize a window or switch between maximized windows. A short capture burst
   selects the color next to the taskbar; afterward the capture timer stops.
6. **Fallback color** sets the initial opaque color until a reliable sample
   is confirmed. Closing/restoring the maximized window returns to the normal
   configured appearance.

The original **Dynamic** option remains available and still samples periodically.
To test the new event-driven behavior, select **Dynamic v2** explicitly. Scroll,
selection and title notifications depend on the application; automatic content
or video changes may retain the previous color until another supported event.
See [Dynamic v2 behavior](dynamic-v2.md).

The same appearance supports bottom, left and right taskbars. Use the taskbar
position controls provided by the configured Windows/ExplorerPatcher setup;
Dynamic follows the actual taskbar geometry. The top edge is outside this
experiment's scope.

When upgrading, exit the old build first. If the upstream development build
requests a Windows restart because Explorer holds an older DLL, restart Windows
and launch the new folder once. Do not repeatedly launch overlapping instances.

## Settings and exit

In the portable build, `settings.json` lives beside the executable and is saved
through the existing application settings mechanism. Retain your own copy
before replacing a previous portable installation. Extracting a new build into
a separate folder keeps its portable settings separate.

Select another appearance to stop using Dynamic for that state. Choose **Exit**
to close the application and restore the taskbar appearance managed by the
existing TranslucentTB exit path. This experimental ZIP does not require an
installer or changes to Windows security settings.

## Known limits

Classic taskbar glyphs follow the system theme and can have poor contrast on
some Dynamic backgrounds; the modern XAML taskbar adapts its glyph theme. Color
tests do not establish readability. See the validation report for recovery,
display, scaling and other tested or unavailable combinations.

GDI is selected using the existing approximate [resource comparison](dynamic-resources.md).
Download the **Dynamic v2** release asset from this fork's [releases](https://github.com/arturito-agent/TranslucentTB/releases).
Its `BUILD.json` pins the native source and bundled documentation; `SHA256SUMS`
verifies each included file. See [v2 validation and approximations](dynamic-v2.md).
