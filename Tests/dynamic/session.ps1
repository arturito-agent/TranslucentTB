param(
    [Parameter(Mandatory=$true)][ValidateSet('Query','Exit')][string] $Action,
    [Parameter(Mandatory=$true)][string] $ExecutablePath,
    [Parameter(Mandatory=$true)][string] $Output
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicSession {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll",SetLastError=true)] public static extern bool PostMessage(IntPtr window,uint msg,IntPtr wp,IntPtr lp);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr window,uint msg,UIntPtr wp,IntPtr lp,uint flags,uint timeout,out UIntPtr result);
    public static ulong Read(IntPtr window,uint message,uint field) {
        UIntPtr result;
        if(SendMessageTimeout(window,message,(UIntPtr)field,IntPtr.Zero,2,1000,out result)==IntPtr.Zero) throw new InvalidOperationException("Worker query failed");
        return result.ToUInt64();
    }
}
'@
$worker = [DynamicSession]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow')
if ($worker -eq [IntPtr]::Zero) { throw 'No TranslucentTB worker on this desktop' }
$targetId = [uint32]0
[void][DynamicSession]::GetWindowThreadProcessId($worker,[ref]$targetId)
$target = Get-Process -Id $targetId
if ([IO.Path]::GetFullPath($target.Path) -ne [IO.Path]::GetFullPath($ExecutablePath)) { throw 'Refusing to operate a different application instance' }
if ($Action -eq 'Exit') {
    $window = [DynamicSession]::FindWindow('TrayWindow','TranslucentTB (Dev)')
    if ($window -eq [IntPtr]::Zero) { throw 'Development tray window missing' }
    $windowOwner = [uint32]0
    [void][DynamicSession]::GetWindowThreadProcessId($window,[ref]$windowOwner)
    if ($windowOwner -ne $targetId) { throw 'Tray/worker ownership mismatch' }
    if (-not [DynamicSession]::PostMessage($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)) { throw 'Graceful close request failed' }
    if (-not $target.WaitForExit(15000)) { throw 'Application has not completed graceful exit' }
    [pscustomobject]@{action=$Action;pid=$targetId;exited=$true} | ConvertTo-Json | Set-Content -Encoding UTF8 $Output
} else {
    $message = [DynamicSession]::RegisterWindowMessage('TTB_QueryDynamicStats')
    $names = @('samples','changes','applications','rgb','run_length','timer','paused','last_sample_tick')
    $result = [ordered]@{action=$Action;pid=$targetId;qpc_ticks=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency}
    for ($i=0;$i -lt $names.Count;$i++) { $result[$names[$i]]=[DynamicSession]::Read($worker,$message,$i) }
    $result['protocol_marker']=[DynamicSession]::Read($worker,$message,255)
    $result['capabilities']=[DynamicSession]::Read($worker,$message,254)
    if($result.protocol_marker -eq 0x44594E01 -and ($result.capabilities -band 1)) {
        $result['captured_frames']=[DynamicSession]::Read($worker,$message,8)
        $result['capture_timeouts']=[DynamicSession]::Read($worker,$message,9)
        $result['capture_failures']=[DynamicSession]::Read($worker,$message,10)
    }
    [pscustomobject]$result | ConvertTo-Json | Set-Content -Encoding UTF8 $Output
}
