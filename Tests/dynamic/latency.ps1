param(
    [Parameter(Mandatory=$true)][string] $Output,
    [ValidateSet('Internal','Focus')][string] $Mode = 'Internal',
    [int] $Trials = 30
)
$ErrorActionPreference = 'Stop'
if ($Trials -lt 1 -or (Test-Path -LiteralPath $Output)) { throw 'Choose a new output file and positive trial count' }
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicLatency {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    public static IntPtr Taskbar() { return FindWindow("Shell_TrayWnd",null); }
    public static IntPtr Worker() { return FindWindow("TTB_WorkerWindow","TTB_WorkerWindow"); }
    public static ulong? Rgb(IntPtr worker) {
        UIntPtr r;
        if(SendMessageTimeout(worker,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)3,IntPtr.Zero,2,100,out r)==IntPtr.Zero) return null;
        return r.ToUInt64();
    }
    public static uint PixelRgb(int x,int y) {
        IntPtr dc=GetDC(IntPtr.Zero);
        try { uint bgr=GetPixel(dc,x,y);return ((bgr&255)<<16)|(bgr&0xff00)|((bgr>>16)&255); }
        finally { ReleaseDC(IntPtr.Zero,dc); }
    }
}
'@
$worker = [DynamicLatency]::Worker()
if ($worker -eq [IntPtr]::Zero) { throw 'No candidate worker' }
$rect = New-Object DynamicLatency+Rect
if (-not [DynamicLatency]::GetWindowRect([DynamicLatency]::Taskbar(),[ref]$rect)) { throw 'No real taskbar' }
$vertical = ($rect.Bottom-$rect.Top) -gt ($rect.Right-$rect.Left)
$x = if($vertical){[int](($rect.Left+$rect.Right)/2)}else{$rect.Left+10}
$y = if($vertical){$rect.Top+10}else{[int](($rect.Top+$rect.Bottom)/2)}
[DynamicFixture]::PrepareDisplay($true)
$a = New-Object DynamicFixture -ArgumentList 'Light',$vertical
$b = New-Object DynamicFixture -ArgumentList 'Dark',$vertical
$a.Text = 'Dynamic latency reference A';$b.Text = 'Dynamic latency reference B'
if($Mode -eq 'Focus') { $b.Show() }
$script:rows = New-Object 'System.Collections.Generic.List[object]'
$script:trial = -1; $script:pending = $false; $script:expected = 0
$script:eventTick = [long]0; $script:failure = $null
$script:nextEvent = [Diagnostics.Stopwatch]::GetTimestamp()+3*[Diagnostics.Stopwatch]::Frequency
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({
    try {
        $now = [Diagnostics.Stopwatch]::GetTimestamp()
        if ($script:pending) {
            $rgb = [DynamicLatency]::Rgb($worker)
            $pixel = [DynamicLatency]::PixelRgb($x,$y)
            $observed = [Diagnostics.Stopwatch]::GetTimestamp()
            $seconds = ($observed-$script:eventTick)/[double][Diagnostics.Stopwatch]::Frequency
            $matched = $rgb -eq $script:expected -and $pixel -eq $script:expected
            if($matched -or $seconds -ge 2.5) {
                $script:rows.Add([pscustomobject]@{
                    mode=$Mode;trial=$script:trial;expected_rgb=$script:expected;confirmed_rgb=$rgb;pixel_rgb=$pixel
                    passed=$matched;latency_seconds=$(if($matched){$seconds}else{$null})
                    event_qpc=$script:eventTick;observed_qpc=$observed;qpc_frequency=[Diagnostics.Stopwatch]::Frequency
                    poll_interval_ms=50
                })
                $script:rows | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
                $script:pending=$false
                if($script:rows.Count -ge $Trials){$a.Close();return}
            }
        }
        if(-not $script:pending -and $now -ge $script:nextEvent) {
            $script:trial++
            $dark = $script:trial%2 -eq 0
            $script:expected = if($dark){1052688}else{16316664}
            $script:eventTick = [Diagnostics.Stopwatch]::GetTimestamp()
            if($Mode -eq 'Focus') {
                if($dark){$b.BringToFront();$b.Activate()}else{$a.BringToFront();$a.Activate()}
            } else {
                $a.Scenario = if($dark){'Dark'}else{'Light'}
                $a.Invalidate()
            }
            $script:pending=$true
            $script:nextEvent=$script:eventTick+3*[Diagnostics.Stopwatch]::Frequency
        }
    } catch { $script:failure=$_.ToString();$a.Close() }
})
$timer.Start()
try { [System.Windows.Forms.Application]::Run($a) }
finally { $timer.Dispose();$b.Dispose();$a.Dispose();[DynamicFixture]::ReleaseDisplay() }
if($script:failure){throw $script:failure}
if($script:rows.Count -ne $Trials -or @($script:rows | Where-Object { -not $_.passed }).Count){throw 'Latency trials failed; inspect CSV'}
Write-Output "Completed $Trials $Mode trials; 50ms observer quantization, separate from resource benchmarks"
