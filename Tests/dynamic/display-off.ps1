param([Parameter(Mandatory=$true)][string] $Output)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Output) { throw 'Choose a new output file' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicPowerTest {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    public static ulong Read(uint field) {
        UIntPtr r;IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");
        if(w==IntPtr.Zero || SendMessageTimeout(w,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero) throw new InvalidOperationException("Worker unavailable");
        return r.ToUInt64();
    }
    public static void Off() {
        UIntPtr ignored;
        SendMessageTimeout(new IntPtr(0xffff),0x112,(UIntPtr)0xf170,new IntPtr(2),2,1000,out ignored);
    }
}
'@
if ([DynamicPowerTest]::Read(5) -ne 1 -or [DynamicPowerTest]::Read(6) -ne 0) { throw 'Begin with effective Dynamic and an awake display' }
$result = [ordered]@{stage='starting';qpc_frequency=[Diagnostics.Stopwatch]::Frequency;start_qpc=[Diagnostics.Stopwatch]::GetTimestamp()}
$capabilities=[DynamicPowerTest]::Read(254)
$extended=($capabilities -band 1) -ne 0
$discovery=($capabilities -band 4) -ne 0
[DynamicPowerTest]::Off()
Start-Sleep -Seconds 2
$result['off_samples_start']=[DynamicPowerTest]::Read(0)
if($extended){$result['off_frames_start']=[DynamicPowerTest]::Read(8)}
if($discovery){$result['off_discovery_queued_start']=[DynamicPowerTest]::Read(23)}
$result['off_timer']=[DynamicPowerTest]::Read(5)
$result['off_paused']=[DynamicPowerTest]::Read(6)
Start-Sleep -Seconds 3
$result['off_samples_end']=[DynamicPowerTest]::Read(0)
if($extended){$result['off_frames_end']=[DynamicPowerTest]::Read(8)}
$result['off_timer_end']=[DynamicPowerTest]::Read(5)
$result['off_paused_end']=[DynamicPowerTest]::Read(6)
if($discovery){$result['off_discovery_queued_end']=[DynamicPowerTest]::Read(23)}
$result['off_passed']=($result.off_timer -eq 0 -and $result.off_paused -eq 1 -and $result.off_samples_start -eq $result.off_samples_end)
$result.off_passed=$result.off_passed -and $result.off_timer_end -eq 0 -and $result.off_paused_end -eq 1
if($extended){$result.off_passed=$result.off_passed -and $result.off_frames_start -eq $result.off_frames_end}
if($discovery){$result.off_passed=$result.off_passed -and $result.off_discovery_queued_start -eq 0 -and $result.off_discovery_queued_end -eq 0}
$result.stage='off-observed-resume-with-real-input-now'
$result | ConvertTo-Json | Set-Content -Encoding UTF8 $Output
# Allow an actual console key to wake the display. No production power setting
# is modified, and this test never prevents the display from sleeping.
Start-Sleep -Seconds 20
$result['resumed_samples']=[DynamicPowerTest]::Read(0)
if($extended){$result['resumed_frames']=[DynamicPowerTest]::Read(8)}
$result['resumed_timer']=[DynamicPowerTest]::Read(5)
$result['resumed_paused']=[DynamicPowerTest]::Read(6)
if($discovery){$result['resumed_discovery_queued']=[DynamicPowerTest]::Read(23)}
$result['resume_passed']=($result.resumed_timer -eq 1 -and $result.resumed_paused -eq 0 -and $result.resumed_samples -gt $result.off_samples_end)
if($discovery){$result.resume_passed=$result.resume_passed -and $result.resumed_discovery_queued -eq 0}
$result['end_qpc']=[Diagnostics.Stopwatch]::GetTimestamp()
$result.stage='complete'
$result | ConvertTo-Json | Set-Content -Encoding UTF8 $Output
if(-not $result.off_passed -or -not $result.resume_passed){throw 'Display off/resume check failed; inspect receipt'}
