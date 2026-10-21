param(
    [Parameter(Mandatory=$true)][string] $ExecutablePath,
    [Parameter(Mandatory=$true)][string] $Output,
    [Parameter(Mandatory=$true)][string] $Commit,
    [ValidateRange(1,10)][int] $DurationSeconds = 6,
    [switch] $ExpectStopped,
    [switch] $PolicyRecompute,
    [switch] $ExpectTransientStops
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Output) { throw 'Choose a new output file' }
if($ExpectTransientStops -and -not $PolicyRecompute){throw 'Transient-stop control requires PolicyRecompute'}
if($ExpectStopped -and $PolicyRecompute){throw 'Choose one negative-control mode'}
# Diagnostic regression only: it deliberately overlaps sent timer/refresh messages.
# Run on an awake classic taskbar with Dynamic active, outside resource trials.
Add-Type @'
using System;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class DynamicRefreshRace {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr w,IntPtr after,string c,string n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr w);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint flags,uint timeout,out UIntPtr result);
    public sealed class Result {
        public ulong BeforeSamples,AfterSamples,BeforeTimer,AfterTimer,Paused;
        public ulong BeforeStops,AfterStops,StopEntryFlags,StopFlags,CurrentFlags;
        public bool SchedulerDiagnostics;
        public int RefreshCalls,TimerCalls,RecomputeCalls,Errors;
    }
    public static uint Owner() {
        uint pid;GetWindowThreadProcessId(FindWindow("TTB_WorkerWindow","TTB_WorkerWindow"),out pid);return pid;
    }
    static ulong Read(IntPtr w,uint query,uint field) {
        UIntPtr r;
        if(SendMessageTimeout(w,query,(UIntPtr)field,IntPtr.Zero,2,100,out r)==IntPtr.Zero)throw new Exception("Read failed");
        return r.ToUInt64();
    }
    public static Result Run(uint expectedPid,int seconds,bool recompute) {
        IntPtr worker=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow"),bar=FindWindow("Shell_TrayWnd",null);
        if(Owner()!=expectedPid||bar==IntPtr.Zero)throw new Exception("Ownership mismatch");
        IntPtr rebar=FindWindowEx(bar,IntPtr.Zero,"ReBarWindow32",null);
        if(rebar==IntPtr.Zero||!IsWindowVisible(rebar))throw new Exception("Requires a visible classic taskbar; the modern TAP path does not use this refresh handler");
        uint query=RegisterWindowMessage("TTB_QueryDynamicStats"),refresh=RegisterWindowMessage("TTB_ForceRefreshTaskbar");
        if(Read(worker,query,255)!=0x44594e01)throw new Exception("Protocol mismatch");
        var result=new Result {BeforeTimer=Read(worker,query,5),BeforeSamples=Read(worker,query,0)};
        result.SchedulerDiagnostics=(Read(worker,query,254)&2)!=0;
        if(recompute && !result.SchedulerDiagnostics)throw new Exception("Policy probe requires scheduler diagnostics");
        if(result.SchedulerDiagnostics)result.BeforeStops=Read(worker,query,20);
        if(result.BeforeTimer!=1||Read(worker,query,6)!=0)throw new Exception("Begin with active Dynamic on an awake unlocked desktop");
        var clock=Stopwatch.StartNew();
        var a=new Thread(()=>{
            while(clock.Elapsed.TotalSeconds<seconds) {
                UIntPtr r;
                if(SendMessageTimeout(worker,refresh,UIntPtr.Zero,bar,2,500,out r)==IntPtr.Zero)Interlocked.Increment(ref result.Errors);
                else Interlocked.Increment(ref result.RefreshCalls);
                Thread.Sleep(1);
            }
        });
        var b=new Thread(()=>{
            while(clock.Elapsed.TotalSeconds<seconds) {
                UIntPtr r;
                // Synthetic unlock notification requests policy recomputation;
                // it does not lock/unlock the Windows session. Begin unlocked.
                uint message=recompute?0x2b1u:0x113u;
                UIntPtr parameter=recompute?(UIntPtr)8:(UIntPtr)0x44594e;
                if(SendMessageTimeout(worker,message,parameter,IntPtr.Zero,2,500,out r)==IntPtr.Zero)Interlocked.Increment(ref result.Errors);
                else if(recompute)Interlocked.Increment(ref result.RecomputeCalls);
                else Interlocked.Increment(ref result.TimerCalls);
                Thread.Sleep(1);
            }
        });
        a.IsBackground=true;b.IsBackground=true;a.Start();b.Start();
        if(!a.Join(seconds*1000+2000)||!b.Join(2000))throw new Exception("Bounded race probe did not finish");
        Thread.Sleep(1000);
        result.AfterTimer=Read(worker,query,5);result.AfterSamples=Read(worker,query,0);result.Paused=Read(worker,query,6);
        if(result.SchedulerDiagnostics) {
            result.AfterStops=Read(worker,query,20);result.StopEntryFlags=Read(worker,query,13);
            result.StopFlags=Read(worker,query,14);result.CurrentFlags=Read(worker,query,11);
        }
        return result;
    }
}
'@
$ownerId = [DynamicRefreshRace]::Owner()
if ($ownerId -eq 0) { throw 'No candidate worker' }
$target = Get-Process -Id $ownerId
if ([IO.Path]::GetFullPath($target.Path) -ne [IO.Path]::GetFullPath($ExecutablePath)) { throw 'Unexpected application instance' }
$result = [DynamicRefreshRace]::Run($ownerId,$DurationSeconds,[bool]$PolicyRecompute)
$passed = $result.Errors -eq 0 -and $result.Paused -eq 0 -and $(if($ExpectStopped){$result.AfterTimer -eq 0}else{$result.AfterTimer -eq 1 -and $result.AfterSamples -gt $result.BeforeSamples})
if($PolicyRecompute){$passed=$passed -and $(if($ExpectTransientStops){$result.AfterStops -gt $result.BeforeStops}else{$result.AfterStops -eq $result.BeforeStops})}
[ordered]@{commit=$Commit;pid=$ownerId;requested_seconds=$DurationSeconds;expect_stopped=[bool]$ExpectStopped;policy_recompute=[bool]$PolicyRecompute;expect_transient_stops=[bool]$ExpectTransientStops;synthetic_notification_only=[bool]$PolicyRecompute;passed=$passed;result=$result} |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Output -Encoding UTF8
if (-not $passed) { throw 'Refresh/timer regression failed; inspect receipt' }
