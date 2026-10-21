param(
    [ValidateSet('Uniform', 'Continuity', 'Changing', 'Interaction', 'Noise', 'Light', 'Dark', 'Border', 'Gradient')]
    [string] $Scenario = 'Continuity',
    [int] $DurationSeconds = 0,
    [ValidateSet('Horizontal', 'Vertical')][string] $Orientation = 'Horizontal',
    [switch] $AllowDisplaySleep,
    [switch] $DefineOnly
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public sealed class DynamicFixture : Form {
    public string Scenario;
    public int Phase;
    public bool Vertical;
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    public static void PrepareDisplay(bool keepAwake) {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        SetThreadExecutionState(keepAwake ? 0x80000003u : 0x80000000u);
    }
    public static void ReleaseDisplay() { SetThreadExecutionState(0x80000000u); }
    public DynamicFixture(string scenario,bool vertical) {
        Scenario = scenario;
        Vertical = vertical;
        Text = "Dynamic synthetic fixture";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = Screen.PrimaryScreen.WorkingArea;
        DoubleBuffered = true;
        AutoScaleMode = AutoScaleMode.None;
        KeyPreview = true;
        KeyDown += (s,e) => { if(e.KeyCode == Keys.Escape) Close(); };
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        Color red = Color.FromArgb(240,0,0), blue = Color.FromArgb(0,0,240);
        if (Scenario == "Light" || Scenario == "Dark") {
            e.Graphics.Clear(Scenario == "Light" ? Color.FromArgb(248,248,248) : Color.FromArgb(16,16,16));
        } else if (Scenario == "Changing") {
            using (var brush = new SolidBrush(Phase % 2 == 0 ? blue : red))
                e.Graphics.FillRectangle(brush, ClientRectangle);
        } else if (Scenario == "Continuity") {
            int size = Vertical ? ClientSize.Height : ClientSize.Width;
            int left = size * 3 / 10;
            int right = size * 7 / 10;
            using (var a = new SolidBrush(red))
            using (var b = new SolidBrush(blue)) {
                e.Graphics.FillRectangle(a, ClientRectangle);
                if (Vertical) e.Graphics.FillRectangle(b,0,left,ClientSize.Width,right-left);
                else e.Graphics.FillRectangle(b,left,0,right-left,ClientSize.Height);
            }
        } else if (Scenario == "Noise" || Scenario == "Gradient") {
            var random = new Random(1338);
            int size = Vertical ? ClientSize.Height : ClientSize.Width;
            for (int i = 0; i < size; ++i) {
                var color = Scenario == "Gradient" ? Color.FromArgb(i*256/size,0,0)
                    : Color.FromArgb(random.Next(256),random.Next(256),random.Next(256));
                using(var brush = new SolidBrush(color)) {
                    if(Vertical) e.Graphics.FillRectangle(brush,0,i,ClientSize.Width,1);
                    else e.Graphics.FillRectangle(brush,i,0,1,ClientSize.Height);
                }
            }
        } else {
            e.Graphics.Clear(Color.FromArgb(32,96,160));
            if(Scenario == "Border") using(var brush = new SolidBrush(red)) {
                if(Vertical) {
                    e.Graphics.FillRectangle(brush,0,0,2,ClientSize.Height);
                    e.Graphics.FillRectangle(brush,ClientSize.Width-2,0,2,ClientSize.Height);
                } else e.Graphics.FillRectangle(brush,0,ClientSize.Height-2,ClientSize.Width,2);
            }
        }
    }
}
'@
if ($DefineOnly) { return }
[DynamicFixture]::PrepareDisplay(-not $AllowDisplaySleep)
$form = New-Object DynamicFixture -ArgumentList $Scenario,($Orientation -eq 'Vertical')
$changeTimer = New-Object System.Windows.Forms.Timer
$changeTimer.Interval = 2000
$interaction = $null
if ($Scenario -eq 'Interaction') {
    $interaction = New-Object DynamicFixture -ArgumentList 'Changing',($Orientation -eq 'Vertical')
    $interaction.Text = 'Dynamic interaction window'
    $interaction.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $interaction.Show()
}
$changeTimer.Add_Tick({
    $form.Phase++
    $form.Invalidate()
    if ($interaction) {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $width = [int]($area.Width * (0.55 + 0.05 * ($form.Phase % 3)))
        $x = if($form.Phase % 2){$area.Left}else{$area.Right-$width}
        $interaction.Bounds = New-Object System.Drawing.Rectangle -ArgumentList $x,$area.Top,$width,$area.Height
        $interaction.Phase = $form.Phase
        $interaction.Invalidate()
        if($form.Phase % 2){$interaction.Activate()}else{$form.Activate()}
    }
})
if ($Scenario -in @('Changing','Interaction')) { $changeTimer.Start() }
$closeTimer = New-Object System.Windows.Forms.Timer
if ($DurationSeconds -gt 0) {
    $closeTimer.Interval = $DurationSeconds * 1000
    $closeTimer.Add_Tick({ $form.Close() })
    $closeTimer.Start()
}
try { [System.Windows.Forms.Application]::Run($form) }
finally {
    $changeTimer.Dispose(); $closeTimer.Dispose()
    if($interaction){$interaction.Dispose()}
    $form.Dispose(); [DynamicFixture]::ReleaseDisplay()
}
