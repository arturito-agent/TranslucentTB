param(
 [Parameter(Mandatory=$true)][string]$Manifest,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [ValidateSet('Left','Right','Bottom')][string[]]$Positions=@('Left','Bottom')
)
$ErrorActionPreference='Stop'
if($Positions.Count -lt 1 -or $Positions.Count -ne @($Positions|Sort-Object -Unique).Count){throw 'Choose distinct positions'}
if(Get-Process TranslucentTB -ErrorAction SilentlyContinue){throw 'Close the existing target'}
$folder=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $folder){throw 'Choose a new output directory'}
$builds=Get-Content -Raw -LiteralPath $Manifest|ConvertFrom-Json
$root=$PSScriptRoot
foreach($scriptName in 'benchmark.ps1','measure.ps1'){
 $source=Get-Content -Raw (Join-Path $root $scriptName)
 $helper=[regex]::Match($source,"(?s)Add-Type @'\r?\n(.*?)\r?\n'@")
 if(-not $helper.Success){throw 'Missing native test helper'}
 Add-Type -TypeDefinition $helper.Groups[1].Value
}
[DynamicMetrics]::PhysicalCoordinates()
. (Join-Path $root 'taskbar-position.ps1') -DefineOnly -Position ($Positions[0])
New-Item -ItemType Directory -Path $folder|Out-Null
$target=$null;$test=$null;$saved=@{};$failure=$null
$shell=Join-Path $PSHOME 'powershell.exe'
function Quote-PS([string]$Value){"'"+$Value.Replace("'","''")+"'"}
function Child([string]$Code){
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
 Start-Process -FilePath $shell -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-EncodedCommand',$encoded) -PassThru
}
function Exit-Owned([string]$Label){
 if($target -and -not $target.HasExited){
  $p=Child "& $(Quote-PS (Join-Path $root 'session.ps1')) -Action Exit -ExecutablePath $(Quote-PS $build.executable) -Output $(Quote-PS (Join-Path $folder ($Label+'-exit.json')))"
  if(-not $p.WaitForExit(20000) -or $p.ExitCode -ne 0 -or -not $target.WaitForExit(1000)){throw 'Graceful target exit failed'}
 }
}
try{
 foreach($backend in 'gdi','dxgi'){
  $build=$builds.$backend
  if((Get-FileHash -Algorithm SHA256 $build.executable).Hash -ne $build.sha256){throw 'Wrong executable'}
  $path=Join-Path (Split-Path -Parent $build.executable) 'settings.json'
  $saved[$path]=if(Test-Path $path){[IO.File]::ReadAllBytes($path)}else{$null}
 }
 foreach($backend in 'gdi','dxgi'){
  $build=$builds.$backend
  $path=Join-Path (Split-Path -Parent $build.executable) 'settings.json'
  @{desktop_appearance=@{accent='dynamic';color='#203040FF'};visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$false};start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false};task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $path
  Get-Process explorer -ErrorAction SilentlyContinue|Stop-Process
  Start-Sleep -Seconds 2
  if(-not(Get-Process explorer -ErrorAction SilentlyContinue)){Start-Process explorer.exe|Out-Null}
  Start-Sleep -Seconds 35
  foreach($position in $Positions){
   Set-ExperimentTaskbarPosition $position
   $orientation=if($position -eq 'Bottom'){'Horizontal'}else{'Vertical'}
   $label="$position-$backend"
   $target=Start-Process -FilePath $build.executable -WorkingDirectory (Split-Path -Parent $build.executable) -PassThru
   $clock=[Diagnostics.Stopwatch]::StartNew()
   while(-not [DynamicBenchmark]::WorkerReady($target.Id,$true,$true)){
    if($target.HasExited -or $clock.Elapsed.TotalSeconds -gt 10){throw 'Owned Dynamic worker unavailable'}
    Start-Sleep -Milliseconds 100
   }
   $bar=[DynamicMetrics]::ReadTaskbar()
   if(-not $bar -or $bar.Edge -ne $position){throw 'Wrong real taskbar edge'}
   $receipt=[ordered]@{backend=$backend;position=$position;commit=$build.commit;executable_sha256=$build.sha256;pid=$target.Id;diagnostic_only=$true;geometry=$bar}
   $receipt|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $folder 'current.json')
   $csv=Join-Path $folder ($label+'.csv')
   $test=Child "try { & $(Quote-PS (Join-Path $root 'functional.ps1')) -Output $(Quote-PS $csv) -Orientation $orientation } catch { `$_|Out-String|Set-Content -Encoding UTF8 $(Quote-PS (Join-Path $folder ($label+'-error.txt')));exit 1 }"
   if(-not $test.WaitForExit(50000) -or $test.ExitCode -ne 0){throw "Functional cases failed: $label"}
   $rows=@(Import-Csv -LiteralPath $csv)
   if($rows.Count -ne 6 -or @($rows|Where-Object passed -ne 'True').Count){throw 'Missing passing color cases'}
   foreach($row in $rows){
    if($row.expected_rgb -ne $row.confirmed_rgb -or $row.expected_rgb -ne $row.taskbar_pixel_rgb){throw 'Incorrect physical taskbar color'}
    if([int]$row.taskbar_left -ne $bar.Left -or [int]$row.taskbar_top -ne $bar.Top -or [int]$row.taskbar_right -ne $bar.Right -or [int]$row.taskbar_bottom -ne $bar.Bottom){throw 'Taskbar geometry changed'}
   }
   Exit-Owned $label;$target=$null;$test=$null
   $receipt|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $folder ($label+'.json'))
  }
 }
 'complete'|Set-Content -Encoding UTF8 (Join-Path $folder 'status.txt')
}catch{$failure=$_.ToString();$failure|Set-Content -Encoding UTF8 (Join-Path $folder 'error.txt')}
finally{
 try{
  if($test -and -not $test.HasExited){[void][DynamicBenchmark]::CloseFixture($test.Id);[void]$test.WaitForExit(10000)}
  Exit-Owned 'cleanup'
 }finally{
  foreach($path in $saved.Keys){if($null -ne $saved[$path]){[IO.File]::WriteAllBytes($path,$saved[$path])}elseif(Test-Path $path){Remove-Item -LiteralPath $path}}
 }
}
if($failure){throw $failure}
