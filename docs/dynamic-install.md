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

## Enable Dynamic

1. Exit any other TranslucentTB instance from its tray menu.
2. Run `TranslucentTB.exe` as the ordinary desktop user.
3. Open its tray menu and choose **Desktop → Dynamic**. Each existing appearance
   state has its own Dynamic option; enabled states and application rules keep
   their normal precedence. For example, **Desktop → Dynamic** with
   **Maximized window → Clear** captures only while Dynamic is effective.
4. **Fallback color** sets the initial color used until a reliable sample is
   confirmed. Dynamic uses an opaque background and ignores fallback alpha.
5. Move or change the content next to the taskbar. The longest continuous color
   segment beside the bar determines its color; separated segments are not
   added together. Sampling runs at a limited cadence, so changes take a short
   time to settle.

The same appearance supports bottom, left and right taskbars. Use the taskbar
position controls provided by the configured Windows/ExplorerPatcher setup;
Dynamic follows the actual taskbar geometry. The top edge is outside this
experiment's scope.

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

Resource comparison, final backend selection and the final release package
are still pending. Do not treat an intermediate CI artifact or successful
functional check as a published low-resource result.
