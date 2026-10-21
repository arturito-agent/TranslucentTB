param(
    [ValidateSet('Bottom','Left','Right')][string] $Position='Bottom',
    [switch] $DefineOnly
)
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ExperimentTaskbar {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w,out Rect r);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint flags,uint timeout,out UIntPtr result);
    public static string Current() {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        Rect r;IntPtr w=FindWindow("Shell_TrayWnd",null);
        if(w==IntPtr.Zero || !GetWindowRect(w,out r)) throw new InvalidOperationException("No real taskbar");
        if(r.Right-r.Left>r.Bottom-r.Top)return r.Top==0?"Top":"Bottom";
        return r.Left==0?"Left":"Right";
    }
    public static void Set(int edge) {
        UIntPtr result;
        if(SendMessageTimeout(FindWindow("Shell_TrayWnd",null),0x400+0x1ca,(UIntPtr)6,new IntPtr(edge),2,2000,out result)==IntPtr.Zero) throw new InvalidOperationException("ExplorerPatcher position request timed out");
    }
}
'@
function Set-ExperimentTaskbarPosition([string] $Target) {
    if([ExperimentTaskbar]::Current() -eq $Target){return}
    $module=Join-Path $env:ProgramFiles 'ExplorerPatcher\ExplorerPatcher.amd64.dll'
    if(-not (Test-Path -LiteralPath $module)){throw 'Lateral position requires the reviewed ExplorerPatcher build'}
    $version=(Get-Item -LiteralPath $module).VersionInfo.FileVersion
    if($version -ne '26100.8457.70.3'){throw "Unreviewed ExplorerPatcher version: $version"}
    $loaded=@((Get-Process explorer).Modules | Where-Object ModuleName -eq 'ep_taskbar.ge.dll')
    if(-not $loaded.Count){throw 'The ExplorerPatcher taskbar module is not loaded'}
    # Same private message used by the reviewed release's ep_gui/GUI.c:
    # TrayUI::_HandleTrayPrivateSettingMessage(6, ABEdge). No registry rewrite.
    $edge=@{Left=0;Right=2;Bottom=3}[$Target]
    [ExperimentTaskbar]::Set($edge)
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    while([ExperimentTaskbar]::Current() -ne $Target) {
        if($deadline.Elapsed.TotalSeconds -gt 5){throw 'The real taskbar did not reach the requested edge'}
        Start-Sleep -Milliseconds 100
    }
}
if(-not $DefineOnly){Set-ExperimentTaskbarPosition $Position}
