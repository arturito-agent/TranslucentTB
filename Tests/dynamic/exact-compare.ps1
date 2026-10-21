param(
 [Parameter(Mandatory=$true)][string]$ExecutablePath,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [switch]$SidesOnly,
 [switch]$WithBrowser,
 [switch]$BrowserOnly,
 [ValidateSet('All','dynamic','dynamic_v2')][string]$OnlyMode='All'
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
$target=$null;$form=$null;$browserWindow=[IntPtr]::Zero;$version='';$position='Bottom'
function Pump([double]$Seconds){$w=[Diagnostics.Stopwatch]::StartNew();while($w.Elapsed.TotalSeconds -lt $Seconds){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25}}
function Save-Rows {$rows|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'observations.json')}
function Snapshot([string]$Stage){
 $target.Refresh()
 $r=[pscustomobject]@{mode=$version;position=$position;stage=$Stage;frames=[ExactProbe]::Read(8);samples=[ExactProbe]::Read(0);changes=[ExactProbe]::Read(1);applications=[ExactProbe]::Read(2);rgb=[ExactProbe]::Read(3);periodic=[ExactProbe]::Read(5);burst=[ExactProbe]::Read(27);remaining=[ExactProbe]::Read(28);paused=[ExactProbe]::Read(6);flags=[ExactProbe]::Read(11);last_sample=[ExactProbe]::Read(7);run_length=[ExactProbe]::Read(4);failures=[ExactProbe]::Read(10);triggers=[ExactProbe]::Read(29);duplicate_colors=[ExactProbe]::Read(30);classic_writes=[ExactProbe]::Read(31);animation_timer=[ExactProbe]::Read(32);events=[ExactProbe]::Read(33);filtered=[ExactProbe]::Read(34);qpc=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency;cpu_seconds=$target.TotalProcessorTime.TotalSeconds;explorer_cpu_seconds=(Get-Process explorer|Measure-Object -Property CPU -Sum).Sum;private_bytes=$target.PrivateMemorySize64;working_set_bytes=$target.WorkingSet64;handles=$target.HandleCount}
 $rows.Add($r);Save-Rows;return $r
}
function Color([uint32]$Rgb){return [Drawing.Color]::FromArgb([int](($Rgb -shr 16)-band 255),[int](($Rgb -shr 8)-band 255),[int]($Rgb-band 255))}
function Assert-Color([uint32]$Rgb){if([ExactProbe]::Read(3) -ne $Rgb -or [ExactProbe]::Pixel($script:pixelX,$script:pixelY) -ne $Rgb){throw ('Exact RGB mismatch: expected {0:X6}, state {1:X6}, physical {2:X6}' -f $Rgb,[ExactProbe]::Read(3),[ExactProbe]::Pixel($script:pixelX,$script:pixelY))}}
try {
 $modes=if($SidesOnly){@('dynamic_v2')}elseif($OnlyMode -ne 'All'){@($OnlyMode)}else{@('dynamic','dynamic_v2')}
 $positions=if($SidesOnly){@('Bottom','Left','Right')}else{@('Bottom')}
 foreach($version in $modes){
  @{desktop_appearance=@{accent='clear';color='#00000000'};visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$true;accent=$version;color='#203040FF'};start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false};task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $settings
  $target=Start-Process $ExecutablePath -WorkingDirectory (Split-Path $ExecutablePath) -PassThru
  $readyWatch=[Diagnostics.Stopwatch]::StartNew();$ready=$false
  do {
   $target.Refresh();if($target.HasExited){throw 'Target exited during initialization'}
   try {
    $owner=[uint32]0;[void][ExactProbe]::GetWindowThreadProcessId([ExactProbe]::FindWindow('TTB_WorkerWindow','TTB_WorkerWindow'),[ref]$owner)
    if($owner -eq $target.Id){$ready=([ExactProbe]::Read(254)-band 16)-ne 0}
   } catch {$ready=$false}
   if(-not $ready){Pump 0.2}
   if($readyWatch.Elapsed.TotalSeconds -gt 30){throw 'Owned worker failed to initialize within 30 seconds'}
  } while(-not $ready)
  Pump 1
  foreach($position in $(if($BrowserOnly){@()}else{$positions})){
   if($SidesOnly){Set-ExperimentTaskbarPosition $position}
   $form=New-Object Windows.Forms.Form
   $form.Text='Dynamic exact reference';$form.BackColor=Color 0xF9F6F3
   $form.WindowState=[Windows.Forms.FormWindowState]::Maximized;$form.Show();$form.Activate();Pump 4
   $bar=New-Object ExactProbe+Rect
   if(-not [ExactProbe]::GetWindowRect([ExactProbe]::FindWindow('Shell_TrayWnd',$null),[ref]$bar)){throw 'No real taskbar'}
   $script:pixelX=if($position -eq 'Bottom'){[int]($bar.Left+3*($bar.Right-$bar.Left)/4)}else{[int](($bar.Left+$bar.Right)/2)}
   $script:pixelY=[int](($bar.Top+$bar.Bottom)/2)
   $null=Snapshot 'initial-color'
   Assert-Color 0xF9F6F3
   $first=Snapshot 'idle-start';Pump $(if($SidesOnly){3}else{15});$last=Snapshot 'idle-end'
   if($version -eq 'dynamic_v2' -and ($first.frames -ne $last.frames -or $last.burst -or $last.animation_timer)){throw 'Unexpected idle capture/animation'}
   if($first.applications -ne $last.applications -or $first.classic_writes -ne $last.classic_writes){throw 'Identical idle RGB reapplied'}
   if(-not $SidesOnly){
    $first=Snapshot 'duplicate-events-start';$w=[Diagnostics.Stopwatch]::StartNew()
    while($w.Elapsed.TotalSeconds -lt 10){[ExactProbe]::NotifyWinEvent(0x800c,$form.Handle,0,0);[ExactProbe]::NotifyWinEvent(0x800b,$form.Handle,0,0);Pump 0.05}
    $last=Snapshot 'duplicate-events-end'
    if($version -eq 'dynamic_v2' -and $first.frames -ne $last.frames){throw 'Duplicate title/geometry events caused capture'}
    if($first.applications -ne $last.applications -or $first.classic_writes -ne $last.classic_writes){throw 'Identical noisy RGB reapplied'}
   }
   # Exercise a one-level change inside the same four-level bucket.
   $form.BackColor=Color 0xFAF6F3;$form.Text='Dynamic exact one-level update';Pump 3
   Assert-Color 0xFAF6F3;$null=Snapshot 'one-level-change'
   $form.BackColor=Color 0x436E99;$form.Text='Dynamic exact blue transition'
   $w=[Diagnostics.Stopwatch]::StartNew()
   while($w.Elapsed.TotalSeconds -lt 3){Pump 0.025;$pixels.Add([pscustomobject]@{mode=$version;position=$position;ms=$w.Elapsed.TotalMilliseconds;rgb=[ExactProbe]::Pixel($pixelX,$pixelY)})}
   Assert-Color 0x436E99;$null=Snapshot 'transition-settled'
   $middle=@($pixels|Where-Object {$_.mode -eq $version -and $_.position -eq $position -and $_.rgb -ne 0xFAF6F3 -and $_.rgb -ne 0x436E99})
   if($middle.Count -eq 0){throw 'No physical intermediate transition color observed'}
   if(-not $SidesOnly){
    $first=Snapshot 'changing-titles-start';$w=[Diagnostics.Stopwatch]::StartNew();$i=0
    while($w.Elapsed.TotalSeconds -lt 8){$form.Text='Dynamic title update '+$i;$i++;Pump 0.1}
    Pump 3;$last=Snapshot 'changing-titles-end'
    if($first.applications -ne $last.applications){throw 'Changing titles reapplied identical RGB'}
    # A paint with no corresponding subscribed WinEvent demonstrates coverage limits.
    $first=Snapshot 'silent-paint-start';$form.BackColor=Color 0xE8DDD1;$form.Refresh();Pump 3;$last=Snapshot 'silent-paint-end'
    if($version -eq 'dynamic'){Assert-Color 0xE8DDD1}
    # The next supported event must eventually converge even during cooldown.
    $form.Text='Dynamic final content event';Pump 3;Assert-Color 0xE8DDD1;$null=Snapshot 'final-event'
   }
   $form.WindowState=[Windows.Forms.FormWindowState]::Normal;Pump 2
   $first=Snapshot 'inactive-start';Pump 2;$last=Snapshot 'inactive-end'
   if($first.frames -ne $last.frames -or $last.periodic -or $last.burst -or $last.animation_timer){throw 'Capture or animation survived deactivation'}
   $form.Close();$form.Dispose();$form=$null
  }
  if($WithBrowser -and -not $SidesOnly){
   $bar=New-Object ExactProbe+Rect
   if(-not [ExactProbe]::GetWindowRect([ExactProbe]::FindWindow('Shell_TrayWnd',$null),[ref]$bar)){throw 'No real taskbar'}
   $script:pixelX=[int]($bar.Left+3*($bar.Right-$bar.Left)/4);$script:pixelY=[int](($bar.Top+$bar.Bottom)/2)
   $edge=Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
   if(-not(Test-Path $edge)){throw 'Owned offline Edge check requires installed Edge'}
   $profile=Join-Path $OutputDirectory ('browser-profile-'+$version)
   $page='file:///'+(Join-Path $PSScriptRoot 'browser-events.html').Replace('\','/')
   Start-Process $edge -ArgumentList @('--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-background-mode','--start-maximized',('--user-data-dir="'+$profile+'"'),('--app='+$page))|Out-Null
   $wait=[Diagnostics.Stopwatch]::StartNew();$browserCandidate=[IntPtr]::Zero
   do{Pump 0.1;$browserCandidate=[ExactProbe]::Browser();if($wait.Elapsed.TotalSeconds -gt 12){throw 'Owned browser app window not found'}}while($browserCandidate -eq [IntPtr]::Zero)
   $browserOwner=[uint32]0;[void][ExactProbe]::GetWindowThreadProcessId($browserCandidate,[ref]$browserOwner)
   $commandLine=(Get-CimInstance Win32_Process -Filter ("ProcessId="+$browserOwner)).CommandLine
   if(-not $commandLine.Contains($profile)){throw 'Refusing an unrelated browser window'}
   $browserWindow=$browserCandidate
   [void][ExactProbe]::ShowWindow($browserWindow,3);[void][ExactProbe]::SetForegroundWindow($browserWindow)
   Pump 5;$null=Snapshot 'browser-idle';if($version -eq 'dynamic'){Assert-Color 0xF9F6F3}
   Pump 7;$null=Snapshot 'browser-title-event';Assert-Color 0x436E99
   Pump 8;$null=Snapshot 'browser-silent-paint'
   if($version -eq 'dynamic'){Assert-Color 0xE8DDD1}
   Pump 8;$null=Snapshot 'browser-final-event';Assert-Color 0xE8DDD1
   [void][ExactProbe]::PostMessage($browserWindow,0x10,[IntPtr]::Zero,[IntPtr]::Zero);$browserWindow=[IntPtr]::Zero;Pump 2
  }
  & (Join-Path $PSScriptRoot 'session.ps1') -Action Exit -ExecutablePath $ExecutablePath -Output (Join-Path $OutputDirectory ($version+'-exit.json'))
  $target=$null;Pump 1
 }
 $pixels|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'transition-pixels.json')
 'complete'|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'status.txt')
} catch {$_|Out-String|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'error.txt');throw}
finally {
 try {
 if($browserWindow -ne [IntPtr]::Zero){[void][ExactProbe]::PostMessage($browserWindow,0x10,[IntPtr]::Zero,[IntPtr]::Zero)}
 if($form){$form.Close();$form.Dispose()}
 if($target -and -not $target.HasExited){& (Join-Path $PSScriptRoot 'session.ps1') -Action Exit -ExecutablePath $ExecutablePath -Output (Join-Path $OutputDirectory 'cleanup-exit.json')}
 } finally {
  if($pixels.Count){$pixels|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'transition-pixels.json')}
  if($null -ne $saved){[IO.File]::WriteAllBytes($settings,$saved)}elseif(Test-Path $settings){Remove-Item $settings}
  [DynamicFixture]::ReleaseDisplay()
 }
}
