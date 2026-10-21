param(
    [Parameter(Mandatory=$true)][string] $Output,
    [Parameter(Mandatory=$true)][ValidateSet('MaximizedClear','TitleRule')][string] $Case
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a new output file'}
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
[DynamicFixture]::PrepareDisplay($true)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicStateTest {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr w);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w,out Rect r);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
    public static uint TaskbarPixel() {
        Rect r;
        if(!GetWindowRect(FindWindow("Shell_TrayWnd",null),out r)) throw new InvalidOperationException("No real taskbar");
        bool vertical=r.Bottom-r.Top>r.Right-r.Left;
        int x=vertical?(r.Left+r.Right)/2:r.Left+10,y=vertical?r.Top+10:(r.Top+r.Bottom)/2;
        IntPtr dc=GetDC(IntPtr.Zero);
        try { uint bgr=GetPixel(dc,x,y);return ((bgr&255)<<16)|(bgr&0xff00)|((bgr>>16)&255); }
        finally { ReleaseDC(IntPtr.Zero,dc); }
    }
    public static ulong Read(uint field) {
        IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");UIntPtr r;
        if(w==IntPtr.Zero || SendMessageTimeout(w,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero) throw new InvalidOperationException("Worker unavailable");
        return r.ToUInt64();
    }
}
'@
# Configure the candidate before launching this script:
# MaximizedClear: Desktop Dynamic, Visible disabled, Maximized Clear enabled.
# TitleRule: Desktop Clear, Visible Clear enabled, title rule "Dynamic rule match"
# using Dynamic. Other optional state overrides must be disabled for both cases.
# Use the known Dynamic fallback #203040FF for this integration fixture.
$stages=@($true,$false,$true,$false,$true)
$script:stage=0;$script:started=$false;$script:baseline=$null;$script:failure=$null
$script:rows=New-Object 'System.Collections.Generic.List[object]'
$form=New-Object DynamicFixture -ArgumentList 'Uniform',$false
$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::Sizable
$clock=[Diagnostics.Stopwatch]::StartNew()
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=100
$timer.Add_Tick({
    try {
        if(-not $script:started) {
            $dynamic=$stages[$script:stage]
            if($Case -eq 'MaximizedClear') {
                $form.Text='Dynamic maximize fixture'
                $form.WindowState=if($dynamic){[System.Windows.Forms.FormWindowState]::Normal}else{[System.Windows.Forms.FormWindowState]::Maximized}
            } else {
                $form.Text=if($dynamic){'Dynamic rule match'}else{'Unmatched synthetic window'}
            }
            $form.Activate()
            $clock.Restart();$script:started=$true;$script:baseline=$null
            return
        }
        if($clock.Elapsed.TotalSeconds -ge 2 -and $null -eq $script:baseline){$script:baseline=[DynamicStateTest]::Read(0)}
        if($clock.Elapsed.TotalSeconds -lt 4){return}
        $dynamic=$stages[$script:stage]
        $samples=[DynamicStateTest]::Read(0);$active=[DynamicStateTest]::Read(5);$rgb=[DynamicStateTest]::Read(3)
        $pixel=[DynamicStateTest]::TaskbarPixel()
        $changes=[DynamicStateTest]::Read(1)
        $expectedRgb=if($changes -gt 0){$rgb}else{0x203040}
        $isMaximized=[DynamicStateTest]::IsZoomed($form.Handle)
        # A sizable fixture's native frame can occupy the adjacent strip. The
        # algorithm cases cover its interior RGB separately. An unreliable frame
        # legitimately uses the known fallback until the first confirmed color.
        $passed=if($dynamic){$active -eq 1 -and $samples -gt $script:baseline -and $pixel -eq $expectedRgb}else{$active -eq 0 -and $samples -eq $script:baseline}
        if($Case -eq 'MaximizedClear'){$passed=$passed -and ($isMaximized -eq (-not $dynamic))}
        $script:rows.Add([pscustomobject]@{case=$Case;stage=$script:stage;expected_dynamic=$dynamic;timer=$active;samples_start=$script:baseline;samples_end=$samples;confirmed_rgb=$rgb;confirmed_changes=$changes;expected_taskbar_rgb=$expectedRgb;taskbar_pixel_rgb=$pixel;maximized=$isMaximized;title=$form.Text;passed=$passed;qpc_ticks=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency})
        $script:rows | Export-Csv -LiteralPath $Output -Encoding UTF8 -NoTypeInformation
        $script:stage++;$script:started=$false
        if($script:stage -ge $stages.Count){$form.Close()}
    } catch {$script:failure=$_.ToString();$form.Close()}
})
$timer.Start()
try{[System.Windows.Forms.Application]::Run($form)}
finally{$timer.Dispose();$form.Dispose();[DynamicFixture]::ReleaseDisplay()}
if($script:failure){throw $script:failure}
if($script:rows.Count -ne $stages.Count -or @($script:rows|Where-Object{-not $_.passed}).Count){throw 'State transitions failed; inspect CSV'}
