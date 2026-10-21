param([Parameter(Mandatory=$true)][string] $Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a new fixture-check output'}
foreach($path in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "PowerShell parser errors in $($path.Name): $errors"}
}
. (Join-Path $PSScriptRoot 'fixture.ps1') -DefineOnly
[DynamicFixture]::PrepareDisplay($false)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FixtureCheck {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr w,uint m,UIntPtr p,IntPtr l,uint f,uint t,out UIntPtr r);
    public static ulong Read(IntPtr window,uint field) {
        UIntPtr result;
        if(SendMessageTimeout(window,RegisterWindowMessage("TTB_QueryFixtureStats"),(UIntPtr)field,IntPtr.Zero,2,1000,out result)==IntPtr.Zero)throw new InvalidOperationException("Fixture query failed");
        return result.ToUInt64();
    }
}
'@
$results=@()
try {
    foreach($scenario in @('Uniform','Changing','Interaction')) {
        $form=$null;$second=$null
        try {
            $form=New-Object DynamicFixture -ArgumentList $scenario,$false
            $form.Show()
            if($scenario -eq 'Interaction') {
                $second=New-Object DynamicFixture -ArgumentList 'Changing',$false
                $second.Text='Dynamic fixture check second'
                $second.Show()
            }
            if($scenario -ne 'Uniform'){$form.StartAnimation($second,33)}
            $watch=[Diagnostics.Stopwatch]::StartNew()
            while($watch.Elapsed.TotalSeconds -lt 2.5) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 10
            }
            $row=[ordered]@{scenario=$scenario;marker=[FixtureCheck]::Read($form.Handle,255);ticks=[FixtureCheck]::Read($form.Handle,0);paints=[FixtureCheck]::Read($form.Handle,1);elapsed_ms=[FixtureCheck]::Read($form.Handle,2);interval_ms=[FixtureCheck]::Read($form.Handle,3)}
            if($row.marker -ne 0x46585401 -or $row.paints -lt 1 -or $row.elapsed_ms -lt 2500){throw 'Fixture counters failed'}
            if($scenario -eq 'Uniform') {
                if($row.ticks -ne 0 -or $row.interval_ms -ne 0){throw 'Static fixture unexpectedly animated'}
            } elseif($row.ticks -lt 10 -or $row.paints -lt 10 -or $row.interval_ms -ne 33){throw 'Animation did not produce repeated paints'}
            $results += [pscustomobject]$row
        } finally {
            if($second){$second.Dispose()}
            if($form){$form.Dispose()}
        }
    }
} finally {[DynamicFixture]::ReleaseDisplay()}
$results | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $Output
Write-Output 'Fixture compile, message protocol and static/animated lifecycle checks passed; no application performance claim.'
