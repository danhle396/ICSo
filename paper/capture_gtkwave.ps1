# =============================================================================
# CE2031 Project 23 - GTKWave screenshots for the report
#   .\paper\capture_gtkwave.ps1          (after run_sim.ps1 and make_figures.py)
#
# Opens the simulation dump traffic_tb.vcd in GTKWave, with
#   paper\gtkwave\T<n>.gtkw    signals of the test, state and lamps shown by name
#                              through the translate filters state.txt / lamp.txt
#   paper\gtkwave\report.rc    larger fonts, readable at the width of the page
# zooms on the window of the test and sets the named markers A..E at the event
# times listed in paper\figures\wave_events.json (written by make_figures.py from
# the same VCD), then takes a picture of the GTKWave window:
#   paper\figures\gtkwave_T5.png   emergency during NS_G
#   paper\figures\gtkwave_T2.png   pedestrian request
# To look at a capture interactively, open the same view by hand:
#   gtkwave -r paper\gtkwave\report.rc traffic_tb.vcd paper\gtkwave\T5.gtkw
# =============================================================================
param([string]$GtkWave = "gtkwave")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
New-Item -ItemType Directory -Force build, paper\figures | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@

$events = Get-Content paper\figures\wave_events.json -Raw | ConvertFrom-Json
$rc = "paper\gtkwave\report.rc"

foreach ($t in "T5", "T2") {
  $e = $events.$t
  $lines = @("gtkwave::setZoomRangeTimes $([int]$e.from)ns $([int]$e.to)ns")
  foreach ($m in $e.markers.PSObject.Properties) {
    $lines += "gtkwave::setNamedMarker $($m.Name) $([int]$m.Value)ns"
  }
  $tcl = Join-Path $root "build\capture_$t.tcl"
  $lines | Set-Content -Encoding ascii $tcl

  $p = Start-Process $GtkWave -PassThru -ArgumentList `
         "-r", $rc, "-S", $tcl, "traffic_tb.vcd", "paper\gtkwave\$t.gtkw"
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 50 -and $h -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 200
    $p.Refresh()
    $h = $p.MainWindowHandle
  }
  if ($h -eq [IntPtr]::Zero) { throw "GTKWave window not found for $t" }
  Start-Sleep -Seconds 2                    # let it draw the traces
  [Win]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 500
  $r = New-Object Win+RECT
  [Win]::GetWindowRect($h, [ref]$r) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [Win]::PrintWindow($h, $hdc, 2) | Out-Null # 2 = PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  $png = Join-Path $root "paper\figures\gtkwave_$t.png"
  $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Stop-Process -Id $p.Id
  Write-Host "wrote $png  ($t, $([int]$e.from) .. $([int]$e.to) ns)"
}
