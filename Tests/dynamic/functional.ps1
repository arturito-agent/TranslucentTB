param(
    [Parameter(Mandatory=$true)][string] $Output,
    [ValidateSet('Horizontal','Vertical')][string] $Orientation = 'Horizontal'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly -Orientation $Orientation
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicFunctional {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
    public static ulong Read(IntPtr w,uint m,uint field) {
        UIntPtr r;
        if(SendMessageTimeout(w,m,(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero) throw new InvalidOperationException("Worker timeout");
        return r.ToUInt64();
    }
    public static uint PixelRgb(int x,int y) {
        IntPtr dc=GetDC(IntPtr.Zero);
        try { uint bgr=GetPixel(dc,x,y); return ((bgr&255)<<16)|(bgr&0xff00)|((bgr>>16)&255); }
        finally { ReleaseDC(IntPtr.Zero,dc); }
    }
}
'@
$worker = [DynamicFunctional]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow')
if ($worker -eq [IntPtr]::Zero) { throw 'Start the candidate in Desktop Dynamic before this test' }
$message = [DynamicFunctional]::RegisterWindowMessage('TTB_QueryDynamicStats')
$tray = [DynamicFunctional]::FindWindow('Shell_TrayWnd','')
$rect = New-Object DynamicFunctional+Rect
if (-not [DynamicFunctional]::GetWindowRect($tray,[ref]$rect)) { throw 'Taskbar rectangle unavailable' }
$vertical = $Orientation -eq 'Vertical'
if (($rect.Bottom-$rect.Top -gt $rect.Right-$rect.Left) -ne $vertical) { throw 'Orientation does not match the real taskbar' }
$pointX = if($vertical){[int](($rect.Left+$rect.Right)/2)}else{$rect.Left+10}
$pointY = if($vertical){$rect.Top+10}else{[int](($rect.Top+$rect.Bottom)/2)}
$stages = @(
    @{name='Continuity';rgb=240},
    @{name='Noise';rgb=240},
    @{name='Light';rgb=16316664},
    @{name='Dark';rgb=1052688},
    @{name='Uniform';rgb=2121888},
    @{name='Border';rgb=2121888}
)
$script:results = New-Object 'System.Collections.Generic.List[object]'
$script:stage = 0
$script:failure = $null
[DynamicFixture]::PrepareDisplay($true)
$form = New-Object DynamicFixture -ArgumentList 'Continuity',$vertical
$clock = [Diagnostics.Stopwatch]::StartNew()
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    try {
        if ($clock.Elapsed.TotalSeconds -lt 4) { return }
        $expected = $stages[$script:stage]
        $rgb = [DynamicFunctional]::Read($worker,$message,3)
        $pixel = [DynamicFunctional]::PixelRgb($pointX,$pointY)
        $row = [pscustomobject]@{
            scenario=$expected.name; expected_rgb=$expected.rgb; confirmed_rgb=$rgb; taskbar_pixel_rgb=$pixel
            passed=($rgb -eq $expected.rgb -and $pixel -eq $expected.rgb)
            captures=[DynamicFunctional]::Read($worker,$message,0)
            changes=[DynamicFunctional]::Read($worker,$message,1)
            applications=[DynamicFunctional]::Read($worker,$message,2)
            run_length=[DynamicFunctional]::Read($worker,$message,4)
            qpc_ticks=[Diagnostics.Stopwatch]::GetTimestamp(); qpc_frequency=[Diagnostics.Stopwatch]::Frequency
            taskbar_left=$rect.Left;taskbar_top=$rect.Top;taskbar_right=$rect.Right;taskbar_bottom=$rect.Bottom
        }
        $script:results.Add($row)
        $script:results | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
        $script:stage++
        if ($script:stage -ge $stages.Count) { $form.Close(); return }
        $form.Scenario = $stages[$script:stage].name
        $form.Invalidate()
        $clock.Restart()
    } catch { $script:failure=$_.ToString(); $form.Close() }
})
$timer.Start()
try { [System.Windows.Forms.Application]::Run($form) }
finally { $timer.Dispose();$form.Dispose();[DynamicFixture]::ReleaseDisplay() }
if ($script:failure) { throw $script:failure }
if ($script:results.Count -ne $stages.Count -or @($script:results | Where-Object { -not $_.passed }).Count) { throw 'Functional cases failed; inspect the CSV' }
Write-Output "Passed $($script:results.Count) live taskbar cases"
