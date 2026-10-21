param(
    [Parameter(Mandatory=$true)][string] $Output,
    [Parameter(Mandatory=$true)][string] $Label,
    [int] $WarmupSeconds = 120,
    [int] $DurationSeconds = 300,
    [int] $IntervalSeconds = 5
)
$ErrorActionPreference = 'Stop'
if ($WarmupSeconds -lt 0 -or $DurationSeconds -lt 1 -or $IntervalSeconds -lt 1) { throw 'Invalid interval' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicMetrics {
    [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr process, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr wnd, uint msg, UIntPtr wp, IntPtr lp, uint flags, uint timeout, out UIntPtr result);
    public static ulong Read(IntPtr window, uint message, uint field) {
        UIntPtr result;
        if(SendMessageTimeout(window,message,(UIntPtr)field,IntPtr.Zero,2,100,out result)==IntPtr.Zero) return 0;
        return result.ToUInt64();
    }
}
'@
$logical = [Environment]::ProcessorCount
$message = [DynamicMetrics]::RegisterWindowMessage('TTB_QueryDynamicStats')
Start-Sleep -Seconds $WarmupSeconds
$watch = [Diagnostics.Stopwatch]::StartNew()
$rows = New-Object 'System.Collections.Generic.List[object]'
$deadline = 0.0
while ($watch.Elapsed.TotalSeconds -le $DurationSeconds) {
    $elapsed = $watch.Elapsed.TotalSeconds
    $window = [DynamicMetrics]::FindWindow('TTB_WorkerWindow',$null)
    foreach ($process in Get-Process -Name TranslucentTB,explorer,dwm -ErrorAction SilentlyContinue) {
        try {
            $process.Refresh()
            $dynamic = $process.ProcessName -eq 'TranslucentTB' -and $window -ne [IntPtr]::Zero
            $rows.Add([pscustomobject]@{
                label=$Label; elapsed_seconds=$elapsed; timestamp_utc=[DateTime]::UtcNow.ToString('o')
                process=$process.ProcessName; pid=$process.Id; logical_processors=$logical
                cpu_seconds=$process.TotalProcessorTime.TotalSeconds
                private_bytes=$process.PrivateMemorySize64; working_set_bytes=$process.WorkingSet64
                peak_working_set_bytes=$process.PeakWorkingSet64; handles=$process.HandleCount
                gdi_objects=[DynamicMetrics]::GetGuiResources($process.Handle,0)
                user_objects=[DynamicMetrics]::GetGuiResources($process.Handle,1)
                dynamic_samples=$(if($dynamic){[DynamicMetrics]::Read($window,$message,0)}else{0})
                dynamic_changes=$(if($dynamic){[DynamicMetrics]::Read($window,$message,1)}else{0})
                dynamic_applications=$(if($dynamic){[DynamicMetrics]::Read($window,$message,2)}else{0})
                dynamic_rgb=$(if($dynamic){[DynamicMetrics]::Read($window,$message,3)}else{0})
                dynamic_run_length=$(if($dynamic){[DynamicMetrics]::Read($window,$message,4)}else{0})
                dynamic_timer=$(if($dynamic){[DynamicMetrics]::Read($window,$message,5)}else{0})
                dynamic_paused=$(if($dynamic){[DynamicMetrics]::Read($window,$message,6)}else{0})
            })
        } catch { Write-Warning "Cannot sample $($process.ProcessName): $($_.Exception.Message)" }
    }
    $deadline += $IntervalSeconds
    $remaining = [Math]::Min($deadline, $DurationSeconds) - $watch.Elapsed.TotalSeconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]($remaining * 1000)) }
    if ($deadline -gt $DurationSeconds) { break }
}
$rows | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8
Write-Output "Saved $($rows.Count) process observations to $Output"
