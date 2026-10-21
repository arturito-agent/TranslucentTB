param(
 [Parameter(Mandatory=$true)][string]$ExecutablePath,
 [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
if((Test-Path $OutputDirectory) -or (Get-Process TranslucentTB -ErrorAction SilentlyContinue)){throw 'Use a fresh output and close existing instances'}
$ExecutablePath=[IO.Path]::GetFullPath($ExecutablePath)
$settings=Join-Path (Split-Path $ExecutablePath) 'settings.json'
$saved=if(Test-Path $settings){[IO.File]::ReadAllBytes($settings)}else{$null}
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
. (Join-Path $PSScriptRoot 'taskbar-position.ps1') -DefineOnly
[DynamicFixture]::PrepareDisplay($true)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class V2Check {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string n);
 [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
 [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
 public static ulong Read(uint field) {UIntPtr r;var w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");if(w==IntPtr.Zero||SendMessageTimeout(w,RegisterWindowMessage("TTB_QueryDynamicStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out r)==IntPtr.Zero)throw new Exception("Worker unavailable");return r.ToUInt64();}
 public static uint Pixel(int x,int y){var dc=GetDC(IntPtr.Zero);try{uint c=GetPixel(dc,x,y);if(c==0xffffffff)throw new Exception("Pixel unavailable");return ((c&255)<<16)|(c&0xff00)|((c>>16)&255);}finally{ReleaseDC(IntPtr.Zero,dc);}}
}
'@
New-Item -ItemType Directory $OutputDirectory|Out-Null
$target=$null;$form=$null;$results=New-Object 'System.Collections.Generic.List[object]'
function Snapshot([string]$Stage){
 $target.Refresh()
 [pscustomobject]@{stage=$Stage;position=$script:position;pid=$target.Id;samples=[V2Check]::Read(0);frames=[V2Check]::Read(8);rgb=[V2Check]::Read(3);failures=[V2Check]::Read(10);periodic_timer=[V2Check]::Read(5);burst_timer=[V2Check]::Read(27);remaining=[V2Check]::Read(28);triggers=[V2Check]::Read(29);qpc=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency;cpu_seconds=$target.TotalProcessorTime.TotalSeconds;private_bytes=$target.PrivateMemorySize64;working_set_bytes=$target.WorkingSet64;handles=$target.HandleCount}
}
function Pump([double]$Seconds){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.Elapsed.TotalSeconds -lt $Seconds){[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25}}
function Save-Rows {$results|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'observations.json')}
try {
 @{desktop_appearance=@{accent='clear';color='#203040FF'};visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$true;accent='dynamic_v2';color='#203040FF'};start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false};task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $settings
 $target=Start-Process $ExecutablePath -WorkingDirectory (Split-Path $ExecutablePath) -PassThru
 Pump 4
 $owner=[uint32]0;[void][V2Check]::GetWindowThreadProcessId([V2Check]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow'),[ref]$owner)
 if($owner -ne $target.Id -or ([V2Check]::Read(254) -band 8) -eq 0){throw 'Expected owned v2 worker'}
 foreach($position in @('Bottom','Left','Right')){
  $script:position=$position
  Set-ExperimentTaskbarPosition $position
  $form=New-Object DynamicFixture -ArgumentList 'Light',($position -ne 'Bottom')
  $form.Text='Dynamic v2 light reference';$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::Sizable
  $form.WindowState=[System.Windows.Forms.FormWindowState]::Maximized;$form.Show();$form.Activate();Pump 5
  $bar=New-Object V2Check+Rect
  if(-not [V2Check]::GetWindowRect([V2Check]::FindWindow('Shell_TrayWnd',$null),[ref]$bar)){throw 'No physical taskbar'}
  $x=if($position -eq 'Bottom'){[int]($bar.Left+3*($bar.Right-$bar.Left)/4)}else{[int](($bar.Left+$bar.Right)/2)};$y=[int](($bar.Top+$bar.Bottom)/2)
  $first=Snapshot 'idle-start';$results.Add($first);Save-Rows
  if($first.rgb -ne 16316664 -or [V2Check]::Pixel($x,$y) -ne 16316664){throw 'Initial real taskbar color mismatch'}
  $idle=if($position -eq 'Bottom'){30}else{5};Pump $idle
  $last=Snapshot 'idle-end';$results.Add($last);Save-Rows
  if($last.frames -ne $first.frames -or $last.samples -ne $first.samples -or $last.periodic_timer -ne 0 -or $last.burst_timer -ne 0 -or $last.remaining -ne 0){throw 'v2 performed periodic work while idle'}
  # Paint alone has no content event: v2 deliberately retains the previous color.
  $form.Scenario='Dark';$form.Invalidate();Pump 2
  $silent=Snapshot 'silent-content';$results.Add($silent);Save-Rows
  if($silent.frames -ne $last.frames -or $silent.rgb -ne $last.rgb){throw 'Unexpected unsignaled capture'}
  # Text changes raise a real accessibility name-change event through WinForms.
  $form.Text='Dynamic v2 dark reference';Pump 3
  $changed=Snapshot 'title-event';$results.Add($changed);Save-Rows
  if($changed.rgb -ne 1052688 -or $changed.frames -le $silent.frames -or [V2Check]::Pixel($x,$y) -ne 1052688 -or $changed.remaining -ne 0){throw 'Event did not update and settle real taskbar color'}
  if($position -eq 'Bottom'){
   $eventStart=Snapshot 'events-start';$results.Add($eventStart)
   for($eventIndex=0;$eventIndex -lt 6;$eventIndex++){
    $form.Scenario=if($eventIndex%2 -eq 0){'Light'}else{'Dark'}
    $form.Text='Dynamic v2 interaction '+$eventIndex;$form.Invalidate();Pump 3
   }
   $eventEnd=Snapshot 'events-end';$results.Add($eventEnd);Save-Rows
   if($eventEnd.frames -le $eventStart.frames -or $eventEnd.remaining -ne 0){throw 'Event sequence did not update and return idle'}
  }
  $form.WindowState=[System.Windows.Forms.FormWindowState]::Normal;Pump 3
  $off=Snapshot 'restored';$results.Add($off);Pump 2
  $offEnd=Snapshot 'restored-idle';$results.Add($offEnd);Save-Rows
  if($off.frames -ne $offEnd.frames -or $offEnd.burst_timer -ne 0 -or $offEnd.remaining -ne 0){throw 'Captures continued after restoration'}
  $form.Close();$form.Dispose();$form=$null
 }
 'complete'|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'status.txt')
} catch {$_|Out-String|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'error.txt');throw}
finally {
 if($form){$form.Close();$form.Dispose()}
 if($target -and -not $target.HasExited){& (Join-Path $PSScriptRoot 'session.ps1') -Action Exit -ExecutablePath $ExecutablePath -Output (Join-Path $OutputDirectory 'exit.json')}
 if($null -ne $saved){[IO.File]::WriteAllBytes($settings,$saved)}elseif(Test-Path $settings){Remove-Item $settings}
 [DynamicFixture]::ReleaseDisplay()
}
