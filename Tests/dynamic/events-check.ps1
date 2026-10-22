param(
 [Parameter(Mandatory=$true)][string]$ExecutablePath,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [switch]$SidesOnly
)
$ErrorActionPreference='Stop'
if((Test-Path $OutputDirectory) -or (Get-Process TranslucentTB -ErrorAction SilentlyContinue)){throw 'Fresh output and no existing target required'}
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
. (Join-Path $PSScriptRoot 'taskbar-position.ps1') -DefineOnly
[DynamicFixture]::PrepareDisplay($true)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ExactProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
 [DllImport("user32.dll")] public static extern void NotifyWinEvent(uint e,IntPtr w,int obj,int child);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
 [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
 [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr w,int n);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
 delegate bool EnumProc(IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr w,System.Text.StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w,uint m,IntPtr p,IntPtr l);
 public static IntPtr Browser(){IntPtr found=IntPtr.Zero;EnumWindows((w,l)=>{var t=new System.Text.StringBuilder(256);GetWindowText(w,t,256);if(t.ToString().StartsWith("Dynamic browser ")){found=w;return false;}return true;},IntPtr.Zero);return found;}
 public static ulong Read(uint field) {UIntPtr r;var w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");if(w==IntPtr.Zero||SendMessageTimeout(w,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero)throw new Exception("Worker unavailable");return r.ToUInt64();}
 public static uint Pixel(int x,int y){var dc=GetDC(IntPtr.Zero);try{uint c=GetPixel(dc,x,y);if(c==0xffffffff)throw new Exception("Pixel unavailable");return ((c&255)<<16)|(c&0xff00)|((c>>16)&255);}finally{ReleaseDC(IntPtr.Zero,dc);}}
}
'@
New-Item -ItemType Directory $OutputDirectory|Out-Null
$ExecutablePath=[IO.Path]::GetFullPath($ExecutablePath)
$settings=Join-Path (Split-Path $ExecutablePath) 'settings.json'
$saved=if(Test-Path $settings){[IO.File]::ReadAllBytes($settings)}else{$null}
$rows=New-Object 'System.Collections.Generic.List[object]'
$pixels=New-Object 'System.Collections.Generic.List[object]'
$target=$null;$form=$null;$second=$null;$browserWindow=[IntPtr]::Zero;$version='';$position='Bottom'
function Pump([double]$Seconds){$w=[Diagnostics.Stopwatch]::StartNew();while($w.Elapsed.TotalSeconds -lt $Seconds){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25}}
function Save-Rows {$rows|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'observations.json')}
function Snapshot([string]$Stage){
 $target.Refresh()
 $r=[pscustomobject]@{mode=$version;position=$position;stage=$Stage;frames=[ExactProbe]::Read(8);samples=[ExactProbe]::Read(0);changes=[ExactProbe]::Read(1);applications=[ExactProbe]::Read(2);rgb=[ExactProbe]::Read(3);periodic=[ExactProbe]::Read(5);burst=[ExactProbe]::Read(27);remaining=[ExactProbe]::Read(28);paused=[ExactProbe]::Read(6);flags=[ExactProbe]::Read(11);last_sample=[ExactProbe]::Read(7);run_length=[ExactProbe]::Read(4);failures=[ExactProbe]::Read(10);triggers=[ExactProbe]::Read(29);duplicate_colors=[ExactProbe]::Read(30);classic_writes=[ExactProbe]::Read(31);animation_timer=[ExactProbe]::Read(32);context_checks=[ExactProbe]::Read(33);filtered=[ExactProbe]::Read(34);qpc=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency;cpu_seconds=$target.TotalProcessorTime.TotalSeconds;explorer_cpu_seconds=(Get-Process explorer|Measure-Object -Property CPU -Sum).Sum;private_bytes=$target.PrivateMemorySize64;working_set_bytes=$target.WorkingSet64;handles=$target.HandleCount}
 $rows.Add($r);Save-Rows;return $r
}
function Color([uint32]$Rgb){return [Drawing.Color]::FromArgb([int](($Rgb -shr 16)-band 255),[int](($Rgb -shr 8)-band 255),[int]($Rgb-band 255))}
function Assert-Color([uint32]$Rgb){if([ExactProbe]::Read(3) -ne $Rgb -or [ExactProbe]::Pixel($script:pixelX,$script:pixelY) -ne $Rgb){throw ('Exact RGB mismatch: expected {0:X6}, state {1:X6}, physical {2:X6}' -f $Rgb,[ExactProbe]::Read(3),[ExactProbe]::Pixel($script:pixelX,$script:pixelY))}}
function Assert-Settled($Before,$After,[int]$MaximumReads) {
 if($version -eq 'chameleon_triggered') {
  if($After.periodic -or $After.burst -or $After.remaining -or ($After.frames-$Before.frames) -gt $MaximumReads){throw 'Unexpected trigger reads or timer left active'}
 }
}
try {
 foreach($version in @('chameleon','chameleon_triggered')) {
  @{desktop_appearance=@{accent='clear';color='#00000000'};visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$true;accent=$version;color='#203040FF'};start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false};task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $settings
  $target=Start-Process $ExecutablePath -WorkingDirectory (Split-Path $ExecutablePath) -PassThru
  $watch=[Diagnostics.Stopwatch]::StartNew();$ready=$false
  do {
   $target.Refresh();if($target.HasExited){throw 'Target exited during initialization'}
   try {$owner=[uint32]0;[void][ExactProbe]::GetWindowThreadProcessId([ExactProbe]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow'),[ref]$owner);$ready=$owner -eq $target.Id -and ([ExactProbe]::Read(254)-band 8)-ne 0} catch {$ready=$false}
   if(-not $ready){Pump 0.2};if($watch.Elapsed.TotalSeconds -gt 30){throw 'Owned worker did not become ready'}
  } while(-not $ready)
  foreach($position in $(if($SidesOnly){@('Bottom','Left','Right')}else{@('Bottom')})) {
   if($SidesOnly){Set-ExperimentTaskbarPosition $position}
   $form=New-Object Windows.Forms.Form;$form.Text='Chameleon source A';$form.BackColor=Color 0xF9F6F3
   $form.WindowState=[Windows.Forms.FormWindowState]::Maximized;$form.Show();$form.Activate();Pump 3
   $bar=New-Object ExactProbe+Rect
   if(-not [ExactProbe]::GetWindowRect([ExactProbe]::FindWindow('Shell_TrayWnd',$null),[ref]$bar)){throw 'No taskbar'}
   $script:pixelX=if($position -eq 'Bottom'){[int]($bar.Left+3*($bar.Right-$bar.Left)/4)}else{[int](($bar.Left+$bar.Right)/2)}
   $script:pixelY=[int](($bar.Top+$bar.Bottom)/2)
   Assert-Color 0xF9F6F3;$null=Snapshot 'initial-color'
   $first=Snapshot 'idle-start';Pump 5;$last=Snapshot 'idle-end'
   Assert-Settled $first $last 0
   if($first.applications -ne $last.applications -or $first.classic_writes -ne $last.classic_writes){throw 'Idle target reapplied'}
   $first=Snapshot 'noisy-events-start';$watch=[Diagnostics.Stopwatch]::StartNew();$i=0
   while($watch.Elapsed.TotalSeconds -lt 3){$form.Text='Chameleon title '+$i;$i++;[ExactProbe]::NotifyWinEvent(0x800c,$form.Handle,0,0);[ExactProbe]::NotifyWinEvent(0x800b,$form.Handle,0,0);Pump 0.03}
   Pump 0.5;$last=Snapshot 'noisy-events-end';Assert-Settled $first $last 0
   if($last.applications -ne $first.applications){throw 'Noisy events reapplied identical color'}
   # Silent paints and titles intentionally cannot trigger the context variant.
   $first=Snapshot 'silent-paint-start';$form.BackColor=Color 0xFAF6F3;$form.Refresh();$form.Text='Chameleon changed title';Pump 2
   Assert-Color $(if($version -eq 'chameleon_triggered'){0xF9F6F3}else{0xFAF6F3})
   $last=Snapshot 'silent-paint-end';Assert-Settled $first $last 0
   # A real change of the responsible maximized HWND must accept an exact 1-level RGB change.
   $second=New-Object Windows.Forms.Form;$second.Text='Chameleon source B';$second.BackColor=Color 0xFAF6F3
   $second.WindowState=[Windows.Forms.FormWindowState]::Maximized
   $first=Snapshot 'switch-new-start';$second.Show();$second.Activate()
   for($j=0;$j -lt 20;$j++){[ExactProbe]::NotifyWinEvent(0x800b,$second.Handle,0,0);[ExactProbe]::NotifyWinEvent(0x800c,$second.Handle,0,0);Pump 0.02}
   Pump 1.5
   Assert-Color 0xFAF6F3;$last=Snapshot 'switch-new-end';Assert-Settled $first $last 2
   # Change back to A and observe the physical transition once.
   $form.BackColor=Color 0x436E99;$form.Activate();$watch=[Diagnostics.Stopwatch]::StartNew()
   while($watch.Elapsed.TotalSeconds -lt 2){Pump 0.025;$pixels.Add([pscustomobject]@{mode=$version;position=$position;ms=$watch.Elapsed.TotalMilliseconds;rgb=[ExactProbe]::Pixel($pixelX,$pixelY)})}
   Assert-Color 0x436E99;$null=Snapshot 'transition-settled'
   if(@($pixels|Where-Object {$_.mode -eq $version -and $_.position -eq $position -and $_.rgb -ne 0xFAF6F3 -and $_.rgb -ne 0x436E99}).Count -eq 0){throw 'No physical intermediate color'}
   # A new HWND with identical RGB needs one read, no confirmation or new animation.
   $second.BackColor=Color 0x436E99;$first=Snapshot 'same-color-switch-start';$second.Activate();Pump 2
   Assert-Color 0x436E99;$last=Snapshot 'same-color-switch-end';Assert-Settled $first $last 1
   if($first.applications -ne $last.applications -or $first.classic_writes -ne $last.classic_writes){throw 'Same RGB source switch reapplied color'}
   if($SidesOnly -and $position -eq 'Bottom') {
    foreach($edge in @('Left','Right','Bottom')) {
     $expected=if($edge -eq 'Right'){0x436E99}else{0xE8DDD1}
     $second.BackColor=Color $expected
     $first=Snapshot ('geometry-'+$edge+'-start');Set-ExperimentTaskbarPosition $edge;Pump 2
     [void][ExactProbe]::GetWindowRect([ExactProbe]::FindWindow('Shell_TrayWnd',$null),[ref]$bar)
     $script:pixelX=if($edge -eq 'Bottom'){[int]($bar.Left+3*($bar.Right-$bar.Left)/4)}else{[int](($bar.Left+$bar.Right)/2)}
     $script:pixelY=[int](($bar.Top+$bar.Bottom)/2)
     Assert-Color $expected;$last=Snapshot ('geometry-'+$edge+'-end');Assert-Settled $first $last 2
    }
   }
   $form.WindowState=[Windows.Forms.FormWindowState]::Normal;$second.WindowState=[Windows.Forms.FormWindowState]::Normal;Pump 1
   $first=Snapshot 'inactive-start';Pump 2;$last=Snapshot 'inactive-end'
   if($first.frames -ne $last.frames -or $last.periodic -or $last.burst -or $last.animation_timer){throw 'Capture survived deactivation'}
   $form.Close();$form.Dispose();$form=$null;$second.Close();$second.Dispose();$second=$null
  }
  & (Join-Path $PSScriptRoot 'session.ps1') -Action Exit -ExecutablePath $ExecutablePath -Output (Join-Path $OutputDirectory ($version+'-exit.json'))
  $target=$null;Pump 0.5
 }
 'complete'|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'status.txt')
} catch {$_|Out-String|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'error.txt');throw}
finally {
 try {
  if($form){$form.Close();$form.Dispose()};if($second){$second.Close();$second.Dispose()}
  if($target -and -not $target.HasExited){& (Join-Path $PSScriptRoot 'session.ps1') -Action Exit -ExecutablePath $ExecutablePath -Output (Join-Path $OutputDirectory 'cleanup-exit.json')}
 } finally {
  $pixels|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'transition-pixels.json')
  if($null -ne $saved){[IO.File]::WriteAllBytes($settings,$saved)}elseif(Test-Path $settings){Remove-Item $settings}
  [DynamicFixture]::ReleaseDisplay()
 }
}
