# =============================================================================
# CE2031 Project 23 - capture GTKWave windows for the report
#   .\paper\capture_gtkwave.ps1          (after run_sim.ps1)
# Opens traffic_tb.vcd with traffic_tb.gtkw (signal list), zooms on the window
# of one directed test (start times read from logs\traffic_tb_seed1.log),
# takes a picture of the GTKWave window and closes it:
#   paper\figures\gtkwave_T5.png   emergency during NS_G
#   paper\figures\gtkwave_T2.png   pedestrian request
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

# start time (ns) of every directed test
$starts = @{}
Get-Content logs\traffic_tb_seed1.log | ForEach-Object {
  if ($_ -match '^TEST_START T(\d+) (\d+) ns') { $starts[[int]$Matches[1]] = [int]$Matches[2] }
}

foreach ($t in 5, 2) {
  $from = $starts[$t]
  $to   = $starts[$t + 1]
  $tcl  = Join-Path $root "build\zoom_T$t.tcl"
  "gtkwave::setZoomRangeTimes ${from}ns ${to}ns" | Set-Content -Encoding ascii $tcl
  $p = Start-Process $GtkWave -ArgumentList "-S", $tcl, "traffic_tb.vcd", "traffic_tb.gtkw" -PassThru
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 50 -and $h -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 200
    $p.Refresh()
    $h = $p.MainWindowHandle
  }
  if ($h -eq [IntPtr]::Zero) { throw "GTKWave window not found for T$t" }
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
  $png = Join-Path $root "paper\figures\gtkwave_T$t.png"
  $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Stop-Process -Id $p.Id
  Write-Host "wrote $png  (T$t, $from .. $to ns)"
}
