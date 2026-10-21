param(
 [Parameter(Mandatory=$true)][string]$Manifest,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [ValidateSet('gdi','dxgi','both')][string]$CaptureBackend='both',
 [ValidateSet('Left','Right','Bottom')][string]$Position='Right'
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$folder=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$selectedBackends=if($CaptureBackend -eq 'both'){@('gdi','dxgi')}else{@($CaptureBackend)}
if(Test-Path $folder){throw 'Choose a new output folder'}
if(Get-Process TranslucentTB -ErrorAction SilentlyContinue){throw 'Close existing target'}
New-Item -ItemType Directory -Path $folder|Out-Null
$builds=Get-Content -Raw -LiteralPath $Manifest|ConvertFrom-Json
foreach($scriptName in 'benchmark.ps1','measure.ps1','functional.ps1'){
 $source=Get-Content -Raw (Join-Path $root $scriptName)
 $helper=[regex]::Match($source,"(?s)Add-Type @'\r?\n(.*?)\r?\n'@")
 if(-not $helper.Success){throw 'Missing native test helper'}
 Add-Type -TypeDefinition $helper.Groups[1].Value
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RecoveryProtocol {
 public sealed class Probe {public string Status;public uint Owner;public int Error;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindow(string c,string n);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern uint RegisterWindowMessage(string n);
 [DllImport("kernel32.dll")]static extern void SetLastError(uint e);
 [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
 public static Probe Read(uint expected){
  var p=new Probe();IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");
  if(w==IntPtr.Zero){p.Status="missing_window";return p;}
  uint owner;GetWindowThreadProcessId(w,out owner);p.Owner=owner;
  if(owner!=expected){p.Status="wrong_owner";return p;}
  uint message=RegisterWindowMessage("TTB_QueryDynamicStats");UIntPtr r;SetLastError(0);
  if(SendMessageTimeout(w,message,(UIntPtr)255,IntPtr.Zero,2,100,out r)==IntPtr.Zero){p.Status="query_unavailable";p.Error=Marshal.GetLastWin32Error();return p;}
  p.Status=r.ToUInt64()==0x44594e01?"ok":"wrong_protocol";return p;
 }
}
'@
[DynamicMetrics]::PhysicalCoordinates()
. (Join-Path $root 'taskbar-position.ps1') -Position $Position -DefineOnly
$message=[DynamicMetrics]::RegisterWindowMessage('TTB_QueryDynamicStats')
$saved=@{};$target=$null;$fixture=$null;$failure=$null
$shell=Join-Path $PSHOME 'powershell.exe'
function Quote-PS([string]$Value){"'"+$Value.Replace("'","''")+"'"}
function Child([string]$Code){$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code));Start-Process -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-EncodedCommand',$encoded) -PassThru}
function Snapshot([switch]$AllowUnavailable) {
 $w=[DynamicMetrics]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow')
 $probe=[RecoveryProtocol]::Read($target.Id)
 if($probe.Status -in @('wrong_owner','wrong_protocol')){throw 'Diagnostic worker identity changed'}
 if($probe.Status -ne 'ok' -and -not $AllowUnavailable){throw 'Diagnostic worker unavailable after recovery'}
 $names=@('attempts','changes','applications','rgb','length','timer','paused','last_sample_tick','frames','timeouts','failures','flags','taskbars','stop_entry_flags','stop_flags','stop_tick','stop_taskbars','stop_desktop','timer_error','desktop','stops','timer_failures')
 $row=[ordered]@{qpc=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency;pid=$target.Id;stats_available=($probe.Status -eq 'ok');protocol_status=$probe.Status;protocol_error=$probe.Error;protocol_owner=$probe.Owner;edge=$null;left=$null;top=$null;right=$null;bottom=$null;dpi=$null}
 for($i=0;$i -lt $names.Count;$i++){$value=if($probe.Status -eq 'ok'){[DynamicMetrics]::Read($w,$message,$i)}else{$null};$row[$names[$i]]=$value;if($null -eq $value){$row.stats_available=$false}}
 if(-not $row.stats_available -and -not $AllowUnavailable){throw 'Incomplete counters after recovery'}
 $bar=[DynamicMetrics]::ReadTaskbar()
 if($bar){$row['edge']=$bar.Edge;$row['left']=$bar.Left;$row['top']=$bar.Top;$row['right']=$bar.Right;$row['bottom']=$bar.Bottom;$row['dpi']=$bar.Dpi}
 [pscustomobject]$row
}
function Exit-Owned([string]$Label){
 if($target -and -not $target.HasExited){
  $p=Child "& $(Quote-PS (Join-Path $root 'session.ps1')) -Action Exit -ExecutablePath $(Quote-PS $build.executable) -Output $(Quote-PS (Join-Path $folder ($Label+'-exit.json')))"
  if(-not $p.WaitForExit(20000) -or $p.ExitCode -ne 0 -or -not $target.WaitForExit(1000)){throw 'Graceful exit failed'}
 }
}
try{
 foreach($backend in $selectedBackends){
  $build=$builds.$backend
  if((Get-FileHash -Algorithm SHA256 $build.executable).Hash -ne $build.sha256){throw 'Wrong executable'}
  $path=Join-Path (Split-Path -Parent $build.executable) 'settings.json'
  $saved[$path]=if(Test-Path $path){[IO.File]::ReadAllBytes($path)}else{$null}
 }
 foreach($backend in $selectedBackends){
  $build=$builds.$backend
  $path=Join-Path (Split-Path -Parent $build.executable) 'settings.json'
  @{desktop_appearance=@{accent='dynamic';color='#203040FF'};visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$false};start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false};task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $path
  Get-Process explorer -ErrorAction SilentlyContinue|Stop-Process
  Start-Sleep -Seconds 2
  if(-not(Get-Process explorer -ErrorAction SilentlyContinue)){Start-Process explorer.exe|Out-Null}
  Start-Sleep -Seconds 35
  Set-ExperimentTaskbarPosition $Position
  $orientation=if($Position -eq 'Bottom'){'Horizontal'}else{'Vertical'}
  $fixture=Child "& $(Quote-PS (Join-Path $root 'fixture.ps1')) -Scenario Uniform -Orientation $orientation -DurationSeconds 180"
  $clock=[Diagnostics.Stopwatch]::StartNew()
  while(-not [DynamicBenchmark]::FixtureExists($fixture.Id)){if($fixture.HasExited -or $clock.Elapsed.TotalSeconds -gt 15){throw 'Fixture unavailable'};Start-Sleep -Milliseconds 100}
  $target=Start-Process -FilePath $build.executable -WorkingDirectory (Split-Path -Parent $build.executable) -PassThru
  $clock.Restart()
  while(-not [DynamicBenchmark]::WorkerReady($target.Id,$true,$true)){if($target.HasExited -or $clock.Elapsed.TotalSeconds -gt 10){throw 'Worker unavailable'};Start-Sleep -Milliseconds 100}
  Start-Sleep -Seconds 4
  $before=Snapshot
  if($before.rgb -ne 2121888 -or $before.frames -lt 1){throw 'Uniform scene did not confirm'}
  [ordered]@{backend=$backend;commit=$build.commit;sha256=$build.sha256;target_pid=$target.Id;fixture_pid=$fixture.Id;diagnostic_only=$true;before=$before}|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $folder "$backend-start.json")
  Get-Process explorer -ErrorAction SilentlyContinue|Stop-Process
  Start-Sleep -Seconds 2
  if(-not(Get-Process explorer -ErrorAction SilentlyContinue)){Start-Process explorer.exe|Out-Null}
  $clock.Restart();$earlyPosition=$false;$latePosition=$false
  $rows=New-Object 'System.Collections.Generic.List[object]'
  while($clock.Elapsed.TotalSeconds -lt 45){
   if($target.HasExited -or $fixture.HasExited){throw 'Owned process exited during recovery'}
   $row=Snapshot -AllowUnavailable;$rows.Add($row)
   $rows|Export-Csv -Encoding UTF8 -NoTypeInformation (Join-Path $folder "$backend-observations.csv")
   if($row.edge -and (($clock.Elapsed.TotalSeconds -gt 8 -and -not $earlyPosition) -or ($clock.Elapsed.TotalSeconds -gt 35 -and -not $latePosition))){
    Set-ExperimentTaskbarPosition $Position
    [DynamicBenchmark]::FitFixture($fixture.Id)
    if($clock.Elapsed.TotalSeconds -gt 35){$latePosition=$true}else{$earlyPosition=$true}
   }
   Start-Sleep -Seconds 1
  }
  $a=Snapshot;Start-Sleep -Seconds 2;$b=Snapshot
  $pixel=if($b.edge){[DynamicFunctional]::PixelRgb($(if($Position -eq 'Bottom'){[int]($b.left+3*($b.right-$b.left)/4)}else{[int](($b.left+$b.right)/2)}),[int](($b.top+$b.bottom)/2))}else{$null}
  $passed=$a.timer -eq 1 -and $b.timer -eq 1 -and $b.paused -eq 0 -and $b.attempts -gt $a.attempts -and $b.rgb -eq 2121888 -and $b.edge -eq $Position -and $b.frames -gt $before.frames -and $pixel -eq 2121888
  [ordered]@{backend=$backend;position=$Position;commit=$build.commit;diagnostic_only=$true;before=$before;after_start=$a;after_end=$b;actual_taskbar_pixel_rgb=$pixel;passed=$passed;observations=$rows.Count}|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $folder "$backend-result.json")
  if(-not $passed){throw "Recovery failed: $backend"}
  Exit-Owned $backend;$target=$null
  [void][DynamicBenchmark]::CloseFixture($fixture.Id);if(-not $fixture.WaitForExit(10000)){throw 'Fixture did not close'};$fixture=$null
 }
 'complete'|Set-Content -Encoding UTF8 (Join-Path $folder 'status.txt')
}catch{$failure=$_.ToString();$failure|Set-Content -Encoding UTF8 (Join-Path $folder 'error.txt')}
finally{
 try{Exit-Owned 'cleanup'}finally{
  if($fixture -and -not $fixture.HasExited){[void][DynamicBenchmark]::CloseFixture($fixture.Id);[void]$fixture.WaitForExit(10000)}
  foreach($path in $saved.Keys){if($null -ne $saved[$path]){[IO.File]::WriteAllBytes($path,$saved[$path])}elseif(Test-Path $path){Remove-Item -LiteralPath $path}}
 }
}
if($failure){throw $failure}
