param(
    [Parameter(Mandatory=$true)][string] $Output,
    [Parameter(Mandatory=$true)][ValidateSet('MaximizedClear','TitleRule','Start','Search','TaskView')][string] $Case,
    [int] $ExpectedProcessId = 0,
    [switch] $CompileOnly
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a new output file'}
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DynamicStateTest {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; }
    public sealed class Probe {public int X,Y;public uint Rgb;public string WindowClass;}
    [StructLayout(LayoutKind.Sequential)] struct MonitorInfo {public uint Size;public Rect Monitor,Work;public uint Flags;}
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr w);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr w,StringBuilder name,int count);
    [StructLayout(LayoutKind.Sequential)] struct Keyboard { public ushort Key,Scan;public uint Flags,Time;public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct Mouse { public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] struct Payload { [FieldOffset(0)] public Keyboard Keyboard;[FieldOffset(0)] public Mouse Mouse; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type;public Payload Data; }
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,Input[] input,int size);
    public static int InputSize() { return Marshal.SizeOf(typeof(Input)); }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w,out Rect r);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr w,uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m,ref MonitorInfo info);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
    public static Probe TaskbarProbe() {
        Rect r;
        if(!GetWindowRect(FindWindow("Shell_TrayWnd",null),out r)) throw new InvalidOperationException("No real taskbar");
        bool vertical=r.Bottom-r.Top>r.Right-r.Left;
        // The leading edge contains the pressed Start button when Start is open.
        // Use empty background in this bounded, few-window synthetic scene.
        int x=vertical?(r.Left+r.Right)/2:r.Left+3*(r.Right-r.Left)/4,y=(r.Top+r.Bottom)/2;
        var name=new StringBuilder(256);GetClassName(WindowFromPoint(new Point{X=x,Y=y}),name,name.Capacity);
        return new Probe{X=x,Y=y,Rgb=PixelAt(x,y),WindowClass=name.ToString()};
    }
    public static uint ReferencePixel() {
        IntPtr bar=FindWindow("Shell_TrayWnd",null);Rect r;
        MonitorInfo info=new MonitorInfo();info.Size=(uint)Marshal.SizeOf(typeof(MonitorInfo));
        if(!GetWindowRect(bar,out r) || !GetMonitorInfo(MonitorFromWindow(bar,2),ref info))throw new InvalidOperationException("No taskbar monitor");
        bool vertical=r.Bottom-r.Top>r.Right-r.Left;
        int x=vertical?(r.Left-info.Monitor.Left<info.Monitor.Right-r.Right?r.Right+4:r.Left-4):(info.Monitor.Left+info.Monitor.Right)/2;
        int y=vertical?(info.Monitor.Top+info.Monitor.Bottom)/2:r.Top-4;
        return PixelAt(x,y);
    }
    static uint PixelAt(int x,int y) {
        IntPtr dc=GetDC(IntPtr.Zero);
        if(dc==IntPtr.Zero)throw new InvalidOperationException("No desktop DC");
        try {
            uint bgr=GetPixel(dc,x,y);
            if(bgr==0xffffffff)throw new InvalidOperationException("Desktop pixel read failed");
            return ((bgr&255)<<16)|(bgr&0xff00)|((bgr>>16)&255);
        }
        finally { ReleaseDC(IntPtr.Zero,dc); }
    }
    public static ulong Read(uint field) {
        IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");UIntPtr r;
        if(w==IntPtr.Zero || SendMessageTimeout(w,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero) throw new InvalidOperationException("Worker unavailable");
        return r.ToUInt64();
    }
    public static bool OwnsWorker(uint expectedPid) {
        IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");uint pid;
        GetWindowThreadProcessId(w,out pid);return w!=IntPtr.Zero && pid==expectedPid;
    }
    public static string ForegroundClass() {
        var name=new StringBuilder(256);GetClassName(GetForegroundWindow(),name,name.Capacity);return name.ToString();
    }
    public static uint ForegroundPid() {
        uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return pid;
    }
    static void Key(ushort key,bool up) {
        var input=new Input {Type=1,Data=new Payload {Keyboard=new Keyboard {Key=key,Flags=up?2u:0u}}};
        if(SendInput(1,new Input[]{input},Marshal.SizeOf(typeof(Input)))!=1)throw new InvalidOperationException("Synthetic test key was not accepted");
    }
    public static void OpenShell(string state,IntPtr fixture) {
        if(GetForegroundWindow()!=fixture)throw new InvalidOperationException("Fixture must be foreground before shell input");
        ushort key=state=="Search"?(ushort)0x53:state=="TaskView"?(ushort)0x09:(ushort)0;
        try { Key(0x5b,false);if(key!=0)Key(key,false); }
        finally { if(key!=0)Key(key,true);Key(0x5b,true); }
    }
    public static void CloseShell() {
        try { Key(0x1b,false); } finally { Key(0x1b,true); }
    }
}
'@
if($CompileOnly){
    $expectedSize=if([IntPtr]::Size -eq 8){40}else{28}
    if([DynamicStateTest]::InputSize() -ne $expectedSize){throw 'Incorrect native INPUT layout'}
    Write-Output 'Shell-state helper compiled; native INPUT layout verified; no desktop input sent.'
    return
}
$shellCase=$Case -in @('Start','Search','TaskView')
if($shellCase -and ($ExpectedProcessId -le 0 -or -not [DynamicStateTest]::OwnsWorker($ExpectedProcessId) -or [DynamicStateTest]::Read(255) -ne 0x44594E01)) { throw 'Shell cases require the owned Dynamic worker PID and protocol' }
[DynamicFixture]::PrepareDisplay($true)
# Configure the candidate before launching this script:
# MaximizedClear: Desktop Dynamic, Visible disabled, Maximized Clear enabled.
# TitleRule: Desktop Clear, Visible Clear enabled, title rule "Dynamic rule match"
# using Dynamic. Other optional state overrides must be disabled for both cases.
# Use the known Dynamic fallback #203040FF for this integration fixture.
# Start/Search/TaskView: Desktop Clear; only the named shell appearance enabled
# with Dynamic and fallback #203040FF. Other overrides disabled. Run outside
# resource measurements, on an awake/unlocked console. These cases use real
# shell keyboard shortcuts, never registered-message state injection.
$stages=@($true,$false,$true,$false,$true)
$script:stage=0;$script:started=$false;$script:baseline=$null;$script:framesBaseline=$null;$script:failure=$null
$script:shellWasRequested=$false
$script:rows=New-Object 'System.Collections.Generic.List[object]'
$form=New-Object DynamicFixture -ArgumentList 'Uniform',$false
$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::Sizable
$clock=[Diagnostics.Stopwatch]::StartNew()
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=100
$timer.Add_Tick({
    try {
        if($ExpectedProcessId -gt 0 -and -not [DynamicStateTest]::OwnsWorker($ExpectedProcessId)){throw 'Worker ownership changed'}
        if(-not $script:started) {
            $dynamic=$stages[$script:stage]
            if($Case -eq 'MaximizedClear') {
                $form.Text='Dynamic maximize fixture'
                $form.WindowState=if($dynamic){[System.Windows.Forms.FormWindowState]::Normal}else{[System.Windows.Forms.FormWindowState]::Maximized}
            } elseif($Case -eq 'TitleRule') {
                $form.Text=if($dynamic){'Dynamic rule match'}else{'Unmatched synthetic window'}
            } else {
                $form.Text='Dynamic shell-state fixture'
                if($dynamic) {
                    if([DynamicStateTest]::Read(5) -ne 0){throw 'Expected Clear before opening the shell view'}
                    $form.Activate()
                    [DynamicStateTest]::OpenShell($Case,$form.Handle)
                    $script:shellWasRequested=$true
                } else {
                    [DynamicStateTest]::CloseShell()
                    $script:shellWasRequested=$false
                }
            }
            if(-not $shellCase){$form.Activate()}
            $clock.Restart();$script:started=$true;$script:baseline=$null
            return
        }
        if($clock.Elapsed.TotalSeconds -ge 2 -and $null -eq $script:baseline){$script:baseline=[DynamicStateTest]::Read(0);$script:framesBaseline=[DynamicStateTest]::Read(8)}
        if($clock.Elapsed.TotalSeconds -lt 4){return}
        $dynamic=$stages[$script:stage]
        $samples=[DynamicStateTest]::Read(0);$active=[DynamicStateTest]::Read(5);$rgb=[DynamicStateTest]::Read(3)
        $frames=[DynamicStateTest]::Read(8)
        $discoveryQueue=if(([DynamicStateTest]::Read(254) -band 4) -ne 0){[DynamicStateTest]::Read(23)}else{$null}
        $probe=[DynamicStateTest]::TaskbarProbe()
        $pixel=$probe.Rgb
        $changes=[DynamicStateTest]::Read(1)
        $expectedRgb=if($changes -gt 0){$rgb}else{0x203040}
        $isMaximized=[DynamicStateTest]::IsZoomed($form.Handle)
        # A sizable fixture's native frame can occupy the adjacent strip. The
        # algorithm cases cover its interior RGB separately. An unreliable frame
        # legitimately uses the known fallback until the first confirmed color.
        $passed=if($dynamic){$active -eq 1 -and $samples -gt $script:baseline -and $pixel -eq $expectedRgb}else{$active -eq 0 -and $samples -eq $script:baseline}
        if($Case -eq 'MaximizedClear'){$passed=$passed -and ($isMaximized -eq (-not $dynamic))}
        if(-not $dynamic){$passed=$passed -and $frames -eq $script:framesBaseline -and ($null -eq $discoveryQueue -or $discoveryQueue -eq 0)}
        $capture=[pscustomobject]@{frames_start=$script:framesBaseline;frames_end=$frames;discovery_queued=$discoveryQueue}
        $script:rows.Add([pscustomobject]@{case=$Case;stage=$script:stage;frames_start=$capture.frames_start;frames_end=$capture.frames_end;discovery_queued=$capture.discovery_queued;expected_dynamic=$dynamic;timer=$active;samples_start=$script:baseline;samples_end=$samples;confirmed_rgb=$rgb;confirmed_changes=$changes;expected_taskbar_rgb=$expectedRgb;taskbar_pixel_rgb=$pixel;taskbar_probe_x=$probe.X;taskbar_probe_y=$probe.Y;taskbar_probe_class=$probe.WindowClass;maximized=$isMaximized;title=$form.Text;foreground_class=[DynamicStateTest]::ForegroundClass();foreground_pid=[DynamicStateTest]::ForegroundPid();expected_worker_pid=$ExpectedProcessId;passed=$passed;qpc_ticks=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency})
        $script:rows | Export-Csv -LiteralPath $Output -Encoding UTF8 -NoTypeInformation
        $script:stage++;$script:started=$false
        if($script:stage -ge $stages.Count){$form.Close()}
    } catch {$script:failure=$_.ToString();$form.Close()}
})
$timer.Start()
try{[System.Windows.Forms.Application]::Run($form)}
finally{
    $timer.Dispose()
    try {if($script:shellWasRequested){[DynamicStateTest]::CloseShell()}}
    finally {$form.Dispose();[DynamicFixture]::ReleaseDisplay()}
}
if($script:failure){throw $script:failure}
if($script:rows.Count -ne $stages.Count -or @($script:rows|Where-Object{-not $_.passed}).Count){throw 'State transitions failed; inspect CSV'}
