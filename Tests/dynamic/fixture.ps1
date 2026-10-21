param(
    [ValidateSet('Uniform', 'Continuity', 'Changing', 'Noise')]
    [string] $Scenario = 'Continuity',
    [int] $DurationSeconds = 0
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;

public sealed class DynamicFixture : Form {
    public string Scenario;
    public int Phase;
    public DynamicFixture(string scenario) {
        Scenario = scenario;
        Text = "Dynamic synthetic fixture";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = Screen.PrimaryScreen.WorkingArea;
        DoubleBuffered = true;
        KeyPreview = true;
        KeyDown += (s,e) => { if(e.KeyCode == Keys.Escape) Close(); };
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        Color red = Color.FromArgb(240,0,0), blue = Color.FromArgb(0,0,240);
        if (Scenario == "Changing") {
            using (var brush = new SolidBrush(Phase % 2 == 0 ? blue : red))
                e.Graphics.FillRectangle(brush, ClientRectangle);
        } else if (Scenario == "Continuity") {
            int left = ClientSize.Width * 3 / 10;
            int right = ClientSize.Width * 7 / 10;
            using (var a = new SolidBrush(red))
            using (var b = new SolidBrush(blue)) {
                e.Graphics.FillRectangle(a, ClientRectangle);
                e.Graphics.FillRectangle(b, left, 0, right-left, ClientSize.Height);
            }
        } else if (Scenario == "Noise") {
            var random = new Random(1338);
            for (int x = 0; x < ClientSize.Width; ++x)
                using(var brush = new SolidBrush(Color.FromArgb(random.Next(256),random.Next(256),random.Next(256))))
                    e.Graphics.FillRectangle(brush,x,0,1,ClientSize.Height);
        } else {
            e.Graphics.Clear(Color.FromArgb(32,96,160));
        }
    }
}
'@
$form = New-Object DynamicFixture($Scenario)
$changeTimer = New-Object System.Windows.Forms.Timer
$changeTimer.Interval = 2000
$changeTimer.Add_Tick({ $form.Phase++; $form.Invalidate() })
if ($Scenario -eq 'Changing') { $changeTimer.Start() }
$closeTimer = New-Object System.Windows.Forms.Timer
if ($DurationSeconds -gt 0) {
    $closeTimer.Interval = $DurationSeconds * 1000
    $closeTimer.Add_Tick({ $form.Close() })
    $closeTimer.Start()
}
try { [System.Windows.Forms.Application]::Run($form) }
finally { $changeTimer.Dispose(); $closeTimer.Dispose(); $form.Dispose() }
