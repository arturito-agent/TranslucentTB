param(
    [Parameter(Mandatory=$true)][string] $Manifest,
    [Parameter(Mandatory=$true)][string] $OutputDirectory,
    [ValidateSet('Static','Interaction','Changing')][string] $Workload = 'Static',
    [ValidateSet('Bottom','Left','Right')][string] $Position = 'Bottom',
    [int] $Repetitions = 3,
    [int] $WarmupSeconds = 120,
    [int] $DurationSeconds = 305,
    [switch] $Smoke
)
$ErrorActionPreference = 'Stop'
if ($Repetitions -lt 1 -or $WarmupSeconds -lt 0 -or $DurationSeconds -lt 1) { throw 'Invalid timing' }
if ($Smoke) { $Repetitions=1;$WarmupSeconds=2;$DurationSeconds=5 }
elseif ($Repetitions -lt 3 -or $WarmupSeconds -lt 120 -or $DurationSeconds -lt 300) { throw 'Full measurements require three repeats, 120s warmup and at least 300s measured' }
if (Get-Process TranslucentTB -ErrorAction SilentlyContinue) { throw 'Close the current instance before starting the suite' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new output directory' }
$builds = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'taskbar-position.ps1') -DefineOnly -Position $Position
foreach ($name in @('baseline','gdi','dxgi')) {
    $build = $builds.$name
    if (-not $build.commit -or -not (Test-Path -LiteralPath $build.executable)) { throw "Missing build: $name" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $build.executable).Hash -ne $build.sha256) { throw "Executable hash mismatch: $name" }
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DynamicBenchmark {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MonitorInfo { public uint Size; public Rect Monitor,Work;public uint Flags; }
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string c,string n);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr w,uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m,ref MonitorInfo info);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr w,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr w,uint m,IntPtr p,IntPtr l);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint flags,uint timeout,out UIntPtr result);
    public static bool WorkerReady(uint expectedPid,bool dynamic) {
        IntPtr w=FindWindow("TTB_WorkerWindow","TTB_WorkerWindow");uint pid;
        if(w==IntPtr.Zero)return false;
        GetWindowThreadProcessId(w,out pid);if(pid!=expectedPid)return false;
        if(!dynamic)return true;
        uint m=RegisterWindowMessage("TTB_QueryDynamicStats");UIntPtr result;
        if(SendMessageTimeout(w,m,(UIntPtr)255,IntPtr.Zero,2,100,out result)==IntPtr.Zero || result.ToUInt64()!=0x44594e01)return false;
        if(SendMessageTimeout(w,m,(UIntPtr)6,IntPtr.Zero,2,100,out result)==IntPtr.Zero || result.ToUInt64()!=0)return false;
        return SendMessageTimeout(w,m,(UIntPtr)5,IntPtr.Zero,2,100,out result)!=IntPtr.Zero && result.ToUInt64()==1;
    }
    public static bool CloseFixture(uint expectedPid) {
        IntPtr w=FindWindow(null,"Dynamic synthetic fixture"); uint pid;
        if(w==IntPtr.Zero) return false;
        GetWindowThreadProcessId(w,out pid);
        return pid==expectedPid && PostMessage(w,0x10,IntPtr.Zero,IntPtr.Zero);
    }
    public static bool FixtureExists(uint expectedPid) {
        IntPtr w=FindWindow(null,"Dynamic synthetic fixture"); uint pid;
        if(w==IntPtr.Zero) return false;
        GetWindowThreadProcessId(w,out pid);return pid==expectedPid;
    }
    public static void FitFixture(uint expectedPid) {
        IntPtr w=FindWindow(null,"Dynamic synthetic fixture");uint pid;
        GetWindowThreadProcessId(w,out pid);
        if(w==IntPtr.Zero || pid!=expectedPid) throw new InvalidOperationException("Fixture ownership mismatch");
        MonitorInfo info=new MonitorInfo();info.Size=(uint)Marshal.SizeOf(typeof(MonitorInfo));
        if(!GetMonitorInfo(MonitorFromWindow(w,2),ref info) || !SetWindowPos(w,IntPtr.Zero,info.Work.Left,info.Work.Top,info.Work.Right-info.Work.Left,info.Work.Bottom-info.Work.Top,0x14)) throw new InvalidOperationException("Fixture geometry update failed");
    }
}
'@
Set-ExperimentTaskbarPosition $Position
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Copy-Item -LiteralPath $Manifest -Destination (Join-Path $OutputDirectory 'builds.json')
$powerShell = Join-Path $PSHOME 'powershell.exe'
function Start-Script([string] $Code) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    Start-Process -FilePath $powerShell -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-EncodedCommand',$encoded) -PassThru
}
function Quote-PS([string] $Value) { "'" + $Value.Replace("'","''") + "'" }
function Exit-Target($Target,[string] $Executable,[string] $Receipt) {
    if ($Target -and -not $Target.HasExited) {
        $exitCode = "& $(Quote-PS (Join-Path $PSScriptRoot 'session.ps1')) -Action Exit -ExecutablePath $(Quote-PS $Executable) -Output $(Quote-PS $Receipt)"
        $closer = Start-Script $exitCode
        if (-not $closer.WaitForExit(20000) -or $closer.ExitCode -ne 0 -or -not $Target.WaitForExit(1000)) { throw 'Graceful target exit failed' }
    }
}
$savedConfigurations = @{}
$fixture = $null; $target = $null; $targetPath = ''; $failure = $null
try {
    foreach ($name in @('baseline','gdi','dxgi')) {
        $path = Join-Path (Split-Path -Parent $builds.$name.executable) 'settings.json'
        $savedConfigurations[$path] = if(Test-Path -LiteralPath $path){[IO.File]::ReadAllBytes($path)}else{$null}
    }
    $scenario = if($Workload -eq 'Static'){'Uniform'}else{$Workload}
    $orientation = if($Position -eq 'Bottom'){'Horizontal'}else{'Vertical'}
    $maximum = ($WarmupSeconds+$DurationSeconds+60)*5*$Repetitions
    $fixtureCode = "& $(Quote-PS (Join-Path $PSScriptRoot 'fixture.ps1')) -Scenario $scenario -Orientation $orientation -DurationSeconds $maximum"
    $fixture = Start-Script $fixtureCode
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while (-not [DynamicBenchmark]::FixtureExists($fixture.Id)) {
        if ($fixture.HasExited -or $deadline.Elapsed.TotalSeconds -gt 20) { throw 'Fixture did not become ready' }
        Start-Sleep -Milliseconds 250
    }
    for ($repeat=1;$repeat -le $Repetitions;$repeat++) {
        $order = if($repeat%2){@('baseline','gdi','baseline','dxgi','baseline')}else{@('baseline','dxgi','baseline','gdi','baseline')}
        for ($phase=0;$phase -lt $order.Count;$phase++) {
            $name = $order[$phase]; $build = $builds.$name
            $label = "$Position-$Workload-r$repeat-p$phase-$name"
            if ($Smoke) { $label = "SMOKE-$label" }
            $targetPath = [IO.Path]::GetFullPath($build.executable)
            $accent = if($name -eq 'baseline'){'opaque'}else{'dynamic'}
            $config = @{
                desktop_appearance=@{accent=$accent;color='#2060A0FF'}
                visible_window_appearance=@{enabled=$false};maximized_window_appearance=@{enabled=$false}
                start_opened_appearance=@{enabled=$false};search_opened_appearance=@{enabled=$false}
                task_view_opened_appearance=@{enabled=$false};battery_saver_appearance=@{enabled=$false}
            }
            $config | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path (Split-Path -Parent $targetPath) 'settings.json')
            # The injected appearance service is pinned until Explorer exits. Restart
            # identically before every phase, including repeated baseline phases.
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process
            Start-Sleep -Seconds 2
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe | Out-Null }
            Start-Sleep -Seconds 5
            Set-ExperimentTaskbarPosition $Position
            if([ExperimentTaskbar]::Current() -ne $Position){throw 'Taskbar edge changed after Explorer restart'}
            [DynamicBenchmark]::FitFixture($fixture.Id)
            $target = Start-Process -FilePath $targetPath -WorkingDirectory (Split-Path -Parent $targetPath) -PassThru
            $readyDeadline=[Diagnostics.Stopwatch]::StartNew()
            while(-not [DynamicBenchmark]::WorkerReady($target.Id,($name -ne 'baseline'))) {
                if($target.HasExited -or $readyDeadline.Elapsed.TotalSeconds -gt 10){throw 'Target not ready: begin with an awake, unlocked actual console'}
                Start-Sleep -Milliseconds 100
            }
            $receipt = [ordered]@{label=$label;diagnostic_only=[bool]$Smoke;commit=$build.commit;executable_sha256=$build.sha256;pid=$target.Id;start_qpc=[Diagnostics.Stopwatch]::GetTimestamp();qpc_frequency=[Diagnostics.Stopwatch]::Frequency;warmup_seconds=$WarmupSeconds;duration_seconds=$DurationSeconds}
            $receipt | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'current-phase.json')
            $csv = Join-Path $OutputDirectory "$label.csv"
            $metricCode = "& $(Quote-PS (Join-Path $PSScriptRoot 'measure.ps1')) -Output $(Quote-PS $csv) -Label '$label' -Commit '$($build.commit)' -TargetProcessId $($target.Id) -WorkloadProcessId $($fixture.Id) -HarnessProcessId $PID -WarmupSeconds $WarmupSeconds -DurationSeconds $DurationSeconds"
            $collector = Start-Script $metricCode
            if (-not $collector.WaitForExit(($WarmupSeconds+$DurationSeconds+30)*1000) -or $collector.ExitCode -ne 0) { throw "Collector failed: $label" }
            if (-not [DynamicBenchmark]::FixtureExists($fixture.Id)) { throw 'Fixture vanished during measurement' }
            $targetRows = @(Import-Csv -LiteralPath $csv | Where-Object role -eq 'target')
            if ($targetRows.Count -lt 2) { throw "Missing target endpoints: $label" }
            foreach($row in $targetRows){if($row.taskbar_edge -ne $Position){throw "Real taskbar edge changed during measurement: $label"}}
            if ($name -ne 'baseline') {
                foreach ($row in $targetRows) {
                    if ($row.dynamic_stats_available -ne 'True' -or $row.capture_stats_available -ne 'True' -or
                        $row.dynamic_timer -ne '1' -or $row.dynamic_paused -ne '0' -or [uint64]$row.captured_frames -lt 1) { throw "Candidate was not capturing: $label" }
                    if ($Workload -eq 'Static' -and $row.dynamic_rgb -ne '2121888') { throw "Incorrect static reference color: $label" }
                }
                if ([uint64]$targetRows[-1].dynamic_samples -le [uint64]$targetRows[0].dynamic_samples -or
                    [uint64]$targetRows[-1].capture_failures -ne [uint64]$targetRows[0].capture_failures) { throw "Capture stopped or failed during measurement: $label" }
            }
            $receipt['end_qpc'] = [Diagnostics.Stopwatch]::GetTimestamp()
            Exit-Target $target $targetPath (Join-Path $OutputDirectory "$label-exit.json")
            $target = $null
            $receipt | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory "$label.json")
        }
    }
    'complete' | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'status.txt')
} catch {
    $failure = $_.ToString()
    $failure | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'error.txt')
} finally {
    try { Exit-Target $target $targetPath (Join-Path $OutputDirectory 'cleanup-exit.json') } catch { $_ | Out-String | Add-Content (Join-Path $OutputDirectory 'error.txt') }
    if ($fixture -and -not $fixture.HasExited) { [void][DynamicBenchmark]::CloseFixture($fixture.Id);[void]$fixture.WaitForExit(10000) }
    foreach ($path in $savedConfigurations.Keys) {
        if ($null -ne $savedConfigurations[$path]) { [IO.File]::WriteAllBytes($path,$savedConfigurations[$path]) }
        elseif(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
}
if ($failure) { throw $failure }
