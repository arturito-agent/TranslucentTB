param(
    [Parameter(Mandatory=$true)][string] $Output,
    [Parameter(Mandatory=$true)][string] $Label,
    [int] $WarmupSeconds = 120,
    [int] $DurationSeconds = 305,
    [int] $IntervalSeconds = 5,
    [int] $TargetProcessId = 0,
    [int] $WorkloadProcessId = 0,
    [int] $HarnessProcessId = 0,
    [string] $Commit = '',
    [switch] $SystemOnly,
    [switch] $IncludeGpu,
    [switch] $IncludeScheduler,
    [switch] $RequireDynamic
)
$ErrorActionPreference = 'Stop'
if ($WarmupSeconds -lt 0 -or $DurationSeconds -lt 1 -or $IntervalSeconds -lt 1) { throw 'Invalid interval' }
if ($RequireDynamic -and $TargetProcessId -le 0) { throw 'RequireDynamic needs an explicit target PID' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicMetrics {
    [StructLayout(LayoutKind.Sequential)] public struct FileTime { public uint Low,High; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle,out FileTime created,out FileTime exited,out FileTime kernel,out FileTime user);
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
    [DllImport("user32.dll",SetLastError=true)] static extern uint GetGuiResources(IntPtr process,uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr wnd,uint msg,UIntPtr wp,IntPtr lp,uint flags,uint timeout,out UIntPtr result);
    public sealed class Counters { public double? CpuSeconds; public uint? GdiObjects,UserObjects; public string Errors=""; }
    public sealed class Taskbar { public int Left,Top,Right,Bottom;public uint Dpi;public string Edge; }
    public static void PhysicalCoordinates() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
    public static Taskbar ReadTaskbar() {
        Rect r;IntPtr w=FindWindow("Shell_TrayWnd",null);
        if(w==IntPtr.Zero || !GetWindowRect(w,out r)) return null;
        return new Taskbar {Left=r.Left,Top=r.Top,Right=r.Right,Bottom=r.Bottom,Dpi=GetDpiForWindow(w),
            Edge=r.Right-r.Left>r.Bottom-r.Top?(r.Top==0?"Top":"Bottom"):(r.Left==0?"Left":"Right")};
    }
    static uint? Gui(IntPtr handle,uint flag,Counters counters) {
        SetLastError(0);
        uint value=GetGuiResources(handle,flag);
        int error=Marshal.GetLastWin32Error();
        if(value==0 && error!=0) { counters.Errors+="GetGuiResources("+flag+"):"+error+";";return null; }
        return value;
    }
    public static Counters ReadCounters(uint pid) {
        Counters counters=new Counters();
        IntPtr handle=OpenProcess(0x1000,false,pid); // PROCESS_QUERY_LIMITED_INFORMATION
        if(handle==IntPtr.Zero) { counters.Errors="OpenProcess:"+Marshal.GetLastWin32Error();return counters; }
        try {
            FileTime c,e,k,u;
            if(GetProcessTimes(handle,out c,out e,out k,out u)) {
                ulong kernel=((ulong)k.High<<32)|k.Low, user=((ulong)u.High<<32)|u.Low;
                counters.CpuSeconds=(kernel+user)/10000000.0;
            } else counters.Errors+="GetProcessTimes:"+Marshal.GetLastWin32Error()+";";
            counters.GdiObjects=Gui(handle,0,counters); counters.UserObjects=Gui(handle,1,counters);
        } finally { CloseHandle(handle); }
        return counters;
    }
    public static ulong? Read(IntPtr window,uint message,uint field) {
        UIntPtr result;
        if(SendMessageTimeout(window,message,(UIntPtr)field,IntPtr.Zero,2,100,out result)==IntPtr.Zero) return null;
        return result.ToUInt64();
    }
    public static IntPtr Fixture(uint expectedPid) {
        IntPtr window=FindWindow(null,"Dynamic synthetic fixture");uint owner;
        GetWindowThreadProcessId(window,out owner);
        return window!=IntPtr.Zero && owner==expectedPid?window:IntPtr.Zero;
    }
}
'@
function Read-Metric([scriptblock] $Read, [string] $Name) {
    try {
        $value = & $Read
        if ($null -eq $value) { $readErrors.Add("${Name}:unavailable"); return $null }
        return $value
    } catch { $readErrors.Add("${Name}:$($_.Exception.Message)"); return $null }
}
$logical = [Environment]::ProcessorCount
[DynamicMetrics]::PhysicalCoordinates()
$message = [DynamicMetrics]::RegisterWindowMessage('TTB_QueryDynamicStats')
$fixtureMessage = [DynamicMetrics]::RegisterWindowMessage('TTB_QueryFixtureStats')
if (Test-Path -LiteralPath $Output) { throw 'Output already exists; choose a new measurement file' }
$gpuOutput = $Output + '.gpu.jsonl'
if ($IncludeGpu -and (Test-Path -LiteralPath $gpuOutput)) { throw 'GPU output already exists; choose a new measurement file' }
$gpu = $null
try {
if ($IncludeGpu) {
    . (Join-Path $PSScriptRoot 'gpu-counters.ps1')
    $gpu = New-Object DynamicGpuCounters
}
Start-Sleep -Seconds $WarmupSeconds
$watch = [Diagnostics.Stopwatch]::StartNew()
$deadline = 0.0
while ($true) {
    $elapsed = $watch.Elapsed.TotalSeconds
    $qpc = [Diagnostics.Stopwatch]::GetTimestamp()
    $bar = [DynamicMetrics]::ReadTaskbar()
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $window = [DynamicMetrics]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow')
    $supportsStats = $window -ne [IntPtr]::Zero -and [DynamicMetrics]::Read($window,$message,255) -eq 0x44594E01
    $capabilities = if($supportsStats){[DynamicMetrics]::Read($window,$message,254)}else{0}
    $captureStats = $supportsStats -and ($capabilities -band 1) -ne 0
    $schedulerAvailable = $supportsStats -and ($capabilities -band 2) -ne 0
    $schedulerStats = $IncludeScheduler -and $schedulerAvailable
    $fixtureWindow = [DynamicMetrics]::Fixture($WorkloadProcessId)
    $fixtureStats = $fixtureWindow -ne [IntPtr]::Zero -and [DynamicMetrics]::Read($fixtureWindow,$fixtureMessage,255) -eq 0x46585401
    $processes = @(if ($SystemOnly) { Get-Process -Name dwm,ep_dwm_svc -ErrorAction SilentlyContinue }
                  else { Get-Process -Name TranslucentTB,explorer,dwm,ep_dwm_svc -ErrorAction SilentlyContinue })
    if ($TargetProcessId -gt 0 -and -not ($processes | Where-Object Id -eq $TargetProcessId)) { throw "Target process $TargetProcessId exited during measurement" }
    foreach ($additionalId in @($WorkloadProcessId,$HarnessProcessId)) {
        if ($additionalId -gt 0) { $processes += Get-Process -Id $additionalId }
    }
    $processes += Get-Process -Id $PID
    foreach ($process in $processes) {
        $readErrors = New-Object 'System.Collections.Generic.List[string]'
        try { $process.Refresh() } catch { $readErrors.Add($_.Exception.Message) }
        $native = [DynamicMetrics]::ReadCounters($process.Id)
        if ($native.Errors) { $readErrors.Add($native.Errors) }
        $dynamic = $supportsStats -and $process.ProcessName -eq 'TranslucentTB'
        $isFixture = $fixtureStats -and $process.Id -eq $WorkloadProcessId
        $row = [ordered]@{
            label=$Label; commit=$Commit; elapsed_seconds=$elapsed; timestamp_utc=[DateTime]::UtcNow.ToString('o')
            qpc_ticks=$qpc; qpc_frequency=[Diagnostics.Stopwatch]::Frequency
            taskbar_edge=$(if($bar){$bar.Edge}else{$null});taskbar_dpi=$(if($bar){$bar.Dpi}else{$null})
            taskbar_left=$(if($bar){$bar.Left}else{$null});taskbar_top=$(if($bar){$bar.Top}else{$null})
            taskbar_right=$(if($bar){$bar.Right}else{$null});taskbar_bottom=$(if($bar){$bar.Bottom}else{$null})
            process=$process.ProcessName; pid=$process.Id; logical_processors=$logical
            role=$(if($process.Id -eq $PID){'observer'}elseif($process.Id -eq $WorkloadProcessId){'workload'}elseif($process.Id -eq $HarnessProcessId){'harness'}elseif($process.ProcessName -eq 'TranslucentTB'){'target'}elseif($process.ProcessName -eq 'dwm'){'compositor'}elseif($process.ProcessName -eq 'ep_dwm_svc'){'taskbar-helper'}else{'shell'})
            cpu_seconds=$native.CpuSeconds
            private_bytes=(Read-Metric { $process.PrivateMemorySize64 } 'private_bytes')
            working_set_bytes=(Read-Metric { $process.WorkingSet64 } 'working_set_bytes')
            peak_working_set_bytes=(Read-Metric { $process.PeakWorkingSet64 } 'peak_working_set_bytes')
            handles=(Read-Metric { $process.HandleCount } 'handles')
            gdi_objects=$native.GdiObjects; user_objects=$native.UserObjects
            dynamic_stats_available=$dynamic
            dynamic_samples=$(if($dynamic){[DynamicMetrics]::Read($window,$message,0)}else{$null})
            dynamic_changes=$(if($dynamic){[DynamicMetrics]::Read($window,$message,1)}else{$null})
            dynamic_applications=$(if($dynamic){[DynamicMetrics]::Read($window,$message,2)}else{$null})
            dynamic_rgb=$(if($dynamic){[DynamicMetrics]::Read($window,$message,3)}else{$null})
            dynamic_run_length=$(if($dynamic){[DynamicMetrics]::Read($window,$message,4)}else{$null})
            dynamic_timer=$(if($dynamic){[DynamicMetrics]::Read($window,$message,5)}else{$null})
            dynamic_paused=$(if($dynamic){[DynamicMetrics]::Read($window,$message,6)}else{$null})
            capture_stats_available=($dynamic -and $captureStats)
            captured_frames=$(if($dynamic -and $captureStats){[DynamicMetrics]::Read($window,$message,8)}else{$null})
            capture_timeouts=$(if($dynamic -and $captureStats){[DynamicMetrics]::Read($window,$message,9)}else{$null})
            capture_failures=$(if($dynamic -and $captureStats){[DynamicMetrics]::Read($window,$message,10)}else{$null})
            scheduler_stats_available=($dynamic -and $schedulerStats)
            scheduler_flags=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,11)}else{$null})
            scheduler_taskbars=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,12)}else{$null})
            scheduler_stop_entry_flags=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,13)}else{$null})
            scheduler_stop_flags=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,14)}else{$null})
            scheduler_stop_tick=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,15)}else{$null})
            scheduler_stop_taskbars=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,16)}else{$null})
            scheduler_stop_desktop=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,17)}else{$null})
            scheduler_timer_error=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,18)}else{$null})
            scheduler_desktop=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,19)}else{$null})
            scheduler_stops=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,20)}else{$null})
            scheduler_timer_failures=$(if($dynamic -and $schedulerStats){[DynamicMetrics]::Read($window,$message,21)}else{$null})
            fixture_stats_available=$isFixture
            fixture_animation_ticks=$(if($isFixture){[DynamicMetrics]::Read($fixtureWindow,$fixtureMessage,0)}else{$null})
            fixture_paints=$(if($isFixture){[DynamicMetrics]::Read($fixtureWindow,$fixtureMessage,1)}else{$null})
            fixture_elapsed_ms=$(if($isFixture){[DynamicMetrics]::Read($fixtureWindow,$fixtureMessage,2)}else{$null})
            fixture_animation_interval_ms=$(if($isFixture){[DynamicMetrics]::Read($fixtureWindow,$fixtureMessage,3)}else{$null})
            errors=($readErrors -join '|')
        }
        $rows.Add([pscustomobject]$row)
    }
    $rows | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8 -Append
    if ($RequireDynamic) {
        $targetRow = @($rows | Where-Object pid -eq $TargetProcessId)[0]
        if ($targetRow.dynamic_stats_available -ne $true -or $targetRow.capture_stats_available -ne $true -or
            $targetRow.dynamic_timer -ne 1 -or $targetRow.dynamic_paused -ne 0) {
            # Query detailed context only on failure, without adding normal-suite
            # IPC overhead. Preserve the original CSV observation as written.
            $context=[ordered]@{label=$Label;commit=$Commit;pid=$TargetProcessId;detected_qpc=$qpc;qpc_frequency=[Diagnostics.Stopwatch]::Frequency;scheduler_available=$schedulerAvailable;timer=$targetRow.dynamic_timer;paused=$targetRow.dynamic_paused}
            if($schedulerAvailable) {
                $names=@('flags','taskbars','stop_entry_flags','stop_flags','stop_tick','stop_taskbars','stop_desktop','timer_error','desktop','stops','timer_failures')
                for($index=0;$index -lt $names.Count;$index++){$context[$names[$index]]=[DynamicMetrics]::Read($window,$message,($index+11))}
                if(($capabilities -band 4) -ne 0){
                    $recoveryNames=@('discovery_requests','discovery_timer','discovery_attempts','discovery_error','discovery_failures')
                    for($index=0;$index -lt $recoveryNames.Count;$index++){$context[$recoveryNames[$index]]=[DynamicMetrics]::Read($window,$message,($index+22))}
                }
            }
            $context|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath ($Output+'.sampler-failure.json')
            throw 'Candidate sampler paused or stopped; retained the failing observation'
        }
    }
    if ($gpu) { Write-DynamicGpuObservation $gpu $rows $gpuOutput $Label $Commit }
    if ($elapsed -ge $DurationSeconds) { break }
    do { $deadline += $IntervalSeconds } while ($deadline -le $watch.Elapsed.TotalSeconds)
    $remaining = [Math]::Min($deadline,$DurationSeconds) - $watch.Elapsed.TotalSeconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining * 1000)) }
}
} finally { if ($gpu) { $gpu.Dispose() } }
Write-Output "Saved process observations through $elapsed seconds to $Output"
