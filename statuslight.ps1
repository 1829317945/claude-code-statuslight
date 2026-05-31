# Claude Code status light — WPF native always-on-top display
# Three vertical traffic-light dots (red / yellow / green), 2cm diameter each.
# True per-pixel alpha transparency (no fuchsia-key artifacts).
# Requires: powershell -STA (single-threaded apartment for WPF)
#
# State file (`state`) contains one word: busy | wait | done | idle
# Alive file (`alive`) heartbeat is written by watchdog.py every 3s

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Drawing

$wslBase = "\\wsl.localhost\Ubuntu"
$dir = "$wslBase\home\dys07\.claude\statuslight"
$stateFile = "$dir\state"
$aliveFile = "$dir\alive"

# ── geometry (1 cm radius = 2 cm diameter per dot) ──────────────
$dpi = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX
$R = [int]($dpi / 2.54)           # 1 cm radius (~38 px @ 96 dpi)
$Gap = [int]($R * 0.63)           # gap between dots, proportional to radius
$Pad = [int]($R * 0.54)           # padding for glow halo
$TopMargin = 18                    # vertical gap from screen top
$LeftCm = 1.0                      # horizontal gap from screen left edge
$leftPx = [int]($dpi / 2.54 * $LeftCm)

# dot centres (x is centred, y stacks top->bottom)
$cx = $Pad + $R
$cy1 = $Pad + $R                                       # red
$cy2 = $cy1 + 2 * $R + $Gap                            # yellow
$cy3 = $cy2 + 2 * $R + $Gap                            # green

$W = 2 * $R + 2 * $Pad
$H = $cy3 + $R + $Pad

# ── colors (WPF System.Windows.Media.Color) ──────────────────────
function WpfColor($r, $g, $b, $a = 255) {
    [System.Windows.Media.Color]::FromArgb($a, $r, $g, $b)
}
# bright (lit) / dim (dark outline — visible on any background)
$redB = WpfColor 255 69 58;   $redD = WpfColor 74 28 24
$yelB = WpfColor 255 214 10;  $yelD = WpfColor 74 62 14
$grnB = WpfColor 48 209 88;   $grnD = WpfColor 20 64 34

function SolidBrush($c) { [System.Windows.Media.SolidColorBrush]::new($c) }

# ── animation state ──────────────────────────────────────────────
$script:phase = 0
$script:doneFlashes = 0
$script:wdMiss = 0
$script:state = "idle"
$TICK_MS = 80
$BLINK = 6            # red blink half-period ~480ms (6 * 80ms)
$DONE_HALF = 3        # green flash half-period ~240ms (3 * 80ms)
$DONE_MAX = 6          # flash 6 times then stay solid
$WD_TICKS = 38         # watchdog check every ~3s (38 * 80ms)
$WD_MAX = 4            # quit after 4 consecutive misses (~12s)
$RAISE_TICKS = 25      # re-assert topmost every ~2s (25 * 80ms)

function Read-State { try { return (Get-Content -Raw $stateFile).Trim() } catch { return "idle" } }

function Is-Alive {
    try {
        $ts = [int](Get-Content -Raw $aliveFile).Trim()
        $now = [int](((Get-Date).ToUniversalTime() - [datetime]"1970-01-01").TotalSeconds)
        return ($now - $ts) -lt 15
    } catch { return $false }
}

# ── WPF window ───────────────────────────────────────────────────
$window = New-Object System.Windows.Window
$window.WindowStyle = "None"
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.WindowStartupLocation = "Manual"
$window.Title = "cc-status"
$window.Width = $W
$window.Height = $H
$window.Left = $leftPx
$window.Top = $TopMargin
$window.IsHitTestVisible = $false   # clicks pass through to windows underneath

# ── canvas ───────────────────────────────────────────────────────
$canvas = New-Object System.Windows.Controls.Canvas
$canvas.Width = $W
$canvas.Height = $H
$window.Content = $canvas

# ── glow ellipses (radial gradient, drawn behind dots) ───────────
function NewGlow($cy) {
    $haloR = $R + $Pad
    $glow = New-Object System.Windows.Shapes.Ellipse
    $glow.Width = 2 * $haloR
    $glow.Height = 2 * $haloR
    [System.Windows.Controls.Canvas]::SetLeft($glow, $cx - $haloR)
    [System.Windows.Controls.Canvas]::SetTop($glow, $cy - $haloR)

    $rb = New-Object System.Windows.Media.RadialGradientBrush
    $rb.GradientOrigin = [System.Windows.Point]::new(0.5, 0.5)
    $rb.Center = [System.Windows.Point]::new(0.5, 0.5)
    $rb.RadiusX = 0.5; $rb.RadiusY = 0.5

    # centre: bright with alpha (color is set dynamically in SetDotColor)
    [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new(
        [System.Windows.Media.Color]::FromArgb(150, 0, 0, 0), 0.55))
    # edge: fully transparent
    [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new(
        [System.Windows.Media.Color]::FromArgb(0, 0, 0, 0), 1.0))

    $glow.Fill = $rb
    return $glow
}

$glow1 = NewGlow $cy1; [void]$canvas.Children.Add($glow1)
$glow2 = NewGlow $cy2; [void]$canvas.Children.Add($glow2)
$glow3 = NewGlow $cy3; [void]$canvas.Children.Add($glow3)

# ── dot ellipses (the three traffic-light circles) ───────────────
function NewDot($cy) {
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 2 * $R
    $dot.Height = 2 * $R
    [System.Windows.Controls.Canvas]::SetLeft($dot, $cx - $R)
    [System.Windows.Controls.Canvas]::SetTop($dot, $cy - $R)
    $dot.Fill = SolidBrush $redD
    return $dot
}
$dot1 = NewDot $cy1; [void]$canvas.Children.Add($dot1)
$dot2 = NewDot $cy2; [void]$canvas.Children.Add($dot2)
$dot3 = NewDot $cy3; [void]$canvas.Children.Add($dot3)

# ── highlight ellipses (glossy specular reflection) ──────────────
function NewHighlight($cy) {
    $hi = New-Object System.Windows.Shapes.Ellipse
    $hr = $R * 0.35
    $hi.Width = 2 * $hr
    $hi.Height = 2 * $hr
    [System.Windows.Controls.Canvas]::SetLeft($hi, $cx - $R * 0.3 - $hr)
    [System.Windows.Controls.Canvas]::SetTop($hi, $cy - $R * 0.3 - $hr)
    $hi.Fill = SolidBrush (WpfColor 255 255 255 90)
    return $hi
}
$hi1 = NewHighlight $cy1; [void]$canvas.Children.Add($hi1)
$hi2 = NewHighlight $cy2; [void]$canvas.Children.Add($hi2)
$hi3 = NewHighlight $cy3; [void]$canvas.Children.Add($hi3)

# ── update one dot + its glow + highlight ────────────────────────
function SetDotColor($dot, $glow, $hi, $c, $bright) {
    $dot.Fill = SolidBrush $c
    if ($bright) {
        $rb = $glow.Fill
        $rb.GradientStops[0].Color = [System.Windows.Media.Color]::FromArgb(150, $c.R, $c.G, $c.B)
        $rb.GradientStops[1].Color = [System.Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B)
        $glow.Opacity = 1.0
        $hi.Opacity = 1.0
    } else {
        $glow.Opacity = 0.0
        $hi.Opacity = 0.0
    }
    return $null
}

# ── dispatcher timer (main animation loop) ───────────────────────
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds($TICK_MS)
$timer.Add_Tick({
    try {
        # ── watchdog: exit when Claude Code is gone ──────────────
        if ($script:phase % $WD_TICKS -eq 0) {
            if (Is-Alive) { $script:wdMiss = 0 }
            else {
                $script:wdMiss++
                if ($script:wdMiss -ge $WD_MAX) { $window.Close(); return }
            }
        }
        # ── re-assert topmost so nothing covers us ───────────────
        if ($script:phase % $RAISE_TICKS -eq 0) {
            $window.Topmost = $false
            $window.Topmost = $true
        }

        $ns = Read-State
        if ($ns -ne $script:state) {
            $script:state = $ns
            $script:phase = 0
            $script:doneFlashes = 0
        }

        # default: all dim
        $c1 = $redD; $c2 = $yelD; $c3 = $grnD
        $b1 = $false; $b2 = $false; $b3 = $false

        switch ($script:state) {
            "busy" {
                # yellow solid — Claude is thinking / running tools
                $c2 = $yelB; $b2 = $true
            }
            "wait" {
                # red blinking ~1 Hz — Claude needs permission or user choice
                if (([math]::Floor($script:phase / $BLINK) % 2) -eq 0) {
                    $c1 = $redB; $b1 = $true
                }
            }
            "done" {
                # green blink 6x then stay solid — task completed
                if ($script:doneFlashes -lt $DONE_MAX) {
                    if (([math]::Floor($script:phase / $DONE_HALF) % 2) -eq 0) {
                        $c3 = $grnB; $b3 = $true
                    }
                    if ($script:phase -gt 0 -and $script:phase % ($DONE_HALF * 2) -eq 0) {
                        $script:doneFlashes++
                    }
                } else {
                    # after 6 flashes, solid green
                    $c3 = $grnB; $b3 = $true
                }
            }
            # "idle": all dim (default) — waiting for user input
        }

        [void](SetDotColor $dot1 $glow1 $hi1 $c1 $b1)
        [void](SetDotColor $dot2 $glow2 $hi2 $c2 $b2)
        [void](SetDotColor $dot3 $glow3 $hi3 $c3 $b3)

        $script:phase++
    } catch {
        # silently ignore tick errors — never crash the display
    }
})

# ── launch ───────────────────────────────────────────────────────
$timer.Start()
$window.Show()
$app = [System.Windows.Application]::new()
$app.ShutdownMode = "OnExplicitShutdown"
$app.Run($window) | Out-Null
