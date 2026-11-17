# =============================================================================
# CE2031 Project 23 - Traffic Light Controller FSM with Emergency Override
# Simulation flow (PLAN 4.5): Icarus Verilog + golden model + mutants.
#
#   .\run_sim.ps1                        # iverilog / vvp / python taken from PATH
#   .\run_sim.ps1 -Bin D:\oss-cad-suite\bin
#
# If the iverilog on PATH understands -g2012 (v11+) the SystemVerilog sources are
# compiled directly. With a legacy build (0.9.7, which does not parse logic /
# always_ff / always_comb / timeunit / assert) every source is first
# down-converted to a logically identical Verilog-2001 file under build\legacy\
# (same converter as labs 1-4; PLAN 2 lists the coding rules it relies on).
# tb\traffic_sva.sv (concurrent SVA) is not given to iverilog: run_modelsim.ps1.
#
#   1. traffic_tb with seeds 1, 7, 2026 -> logs\traffic_tb_seed<N>.log
#      (seed 1 also writes traffic_tb.vcd: open it with traffic_tb.gtkw)
#   2. model\golden.py on each run      -> logs\golden_seed<N>.log
#   3. mutants M1..M6 (PLAN 4.4), seed 1 -> logs\mutant_M<k>.log, logs\golden_M<k>.log
#      every mutant must be caught (testbench FAILED and/or golden FAIL)
#   4. summary on screen and in logs\summary.log
# =============================================================================
param([string]$Bin = "", [string]$Python = "python")

$ErrorActionPreference = "Continue"       # tools print warnings on stderr
Set-Location $PSScriptRoot

$iverilog = if ($Bin) { Join-Path $Bin "iverilog.exe" } else { "iverilog" }
$vvp      = if ($Bin) { Join-Path $Bin "vvp.exe" }      else { "vvp" }
if ($Bin) { $env:PATH = "$Bin;$(Join-Path $Bin '..\lib');$env:PATH" }   # OSS CAD Suite DLLs

New-Item -ItemType Directory -Force logs, build, build\legacy, build\mutants, vectors | Out-Null

$rtl   = @("rtl\strobe_gen.sv", "rtl\sync_debounce.sv", "rtl\clk_divider.sv", "rtl\state_timer.sv",
           "rtl\traffic_fsm.sv", "rtl\bin2bcd8.sv", "rtl\traffic_top.sv")
$bench = @("tb\traffic_checker.sv", "tb\traffic_tb.sv")
$seeds = @(1, 7, 2026)

# ---- Does this iverilog support SystemVerilog-2012 (-g2012)? ----------------
$probe = Join-Path $env:TEMP "iv_probe.sv"
"module p(input logic a, output logic y); always_comb y = a; endmodule" | Set-Content -Encoding ascii $probe
& $iverilog -g2012 -o (Join-Path $env:TEMP "iv_probe.out") $probe 2>$null | Out-Null
$supports2012 = ($LASTEXITCODE -eq 0)
Write-Host ("iverilog -g2012 support: {0}" -f $supports2012) -ForegroundColor Yellow

# ---- Down-convert one SystemVerilog file to Verilog-2001 --------------------
function Convert-Legacy([string]$Src, [string]$OutDir = "build\legacy") {
  $dst = Join-Path $OutDir (Split-Path $Src -Leaf)
  $text = Get-Content -Raw $Src
  # immediate assertion:  assert (C) else ...   ->   if (!(C)) ...
  $text = [regex]::Replace($text, '(?s)\bassert\s*\((.*?)\)\s*else\b', 'if (!($1))')
  # timeunit / timeprecision become the file's `timescale
  $tu = if ($text -match '(?m)^\s*timeunit\s+(\w+)\s*;')      { $Matches[1] } else { '1ns' }
  $tp = if ($text -match '(?m)^\s*timeprecision\s+(\w+)\s*;') { $Matches[1] } else { '1ps' }
  $lines = $text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*timeunit\b' -and $_ -notmatch '^\s*timeprecision\b' }
  $out = @()
  foreach ($l in $lines) {
    $l = $l -replace '\b(parameter|localparam)\s+(int|logic)\b', '$1'
    $l = $l -replace '\bfunction\s+(automatic\s+)?logic\b', 'function $1'
    $l = $l -replace '\bint\b', 'integer'
    $l = $l -replace '\balways_comb\b', 'always @*'
    $l = $l -replace '\balways_ff\b', 'always'
    $l = $l -replace '\b(unique|priority)\s+case\b', 'case'
    $l = $l -replace '\binput\s+logic\b', 'input '
    $l = $l -replace '\boutput\s+logic\b', 'output reg'
    $l = $l -replace '\blogic\b', 'reg'
    $l = $l -replace '\b(\w+)\+\+', '$1 = $1 + 1'
    $l = $l -replace '\$error\s*\("', '$$display("ERROR: '
    $out += $l
  }
  $body = $out -join "`r`n"
  if ($body -notmatch '`timescale') { $body = "``timescale $tu/$tp`r`n" + $body }
  Set-Content -Encoding ascii $dst $body
  return $dst
}

function Resolve-Sources([string[]]$Sources, [string]$OutDir = "build\legacy") {
  if ($supports2012) { return $Sources }
  return ($Sources | ForEach-Object { Convert-Legacy $_ $OutDir })
}

function Compile([string]$Out, [string[]]$Sources) {
  $genArgs = if ($supports2012) { @("-g2012") } else { @() }
  & $iverilog @genArgs -s traffic_tb -o $Out @Sources
  if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $Out" }
}

# Run one simulation and the golden model on its vectors
function Invoke-Run([string]$Sim, [int]$Seed, [string]$Tag, [string]$Log, [string]$GoldenLog, [switch]$Vcd) {
  $plus = @("+seed=$Seed", "+tag=$Tag")
  if ($Vcd) { $plus += "+vcd" }
  $out = & $vvp $Sim @plus
  $out | Set-Content -Encoding ascii $Log
  & $Python -I model\golden.py "vectors\stim_$Tag.txt" "vectors\rtl_$Tag.txt" $GoldenLog | Out-Null
  $tb     = ($out | Select-String -Pattern '^TRAFFIC TB (PASSED|FAILED)' | Select-Object -Last 1).Line
  $cov    = ($out | Select-String -Pattern '^COVERAGE' | Select-Object -Last 1).Line
  $golden = (Get-Content $GoldenLog | Select-Object -Last 1)
  $viol   = @($out | Select-String -Pattern '^\s+(a_\w+)\s+\d+\s+([1-9]\d*)\s*$' |
              ForEach-Object { $_.Matches[0].Groups[1].Value })
  return [pscustomobject]@{ TB = $tb; Coverage = $cov; Golden = $golden; Violated = ($viol -join ",") }
}

$summary = @()
$summary += "CE2031 Project 23 - simulation summary  ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
$summary += "iverilog -g2012: $supports2012 ; sources down-converted: $(-not $supports2012)"

# ---- 1-2. Testbench + golden model, three seeds ------------------------------
Write-Host "`n==== traffic_tb + golden model ====" -ForegroundColor Cyan
$srcs = Resolve-Sources ($rtl + $bench)
Compile "build\traffic_sim" $srcs
$allPass = $true
foreach ($s in $seeds) {
  $r = Invoke-Run "build\traffic_sim" $s "seed$s" "logs\traffic_tb_seed$s.log" "logs\golden_seed$s.log" -Vcd:($s -eq $seeds[0])
  Write-Host ("seed {0,-5} {1}" -f $s, $r.TB)
  Write-Host ("            {0}" -f $r.Coverage)
  Write-Host ("            golden: {0}" -f $r.Golden)
  $summary += ("seed {0,-5} {1}" -f $s, $r.TB)
  $summary += ("            {0}" -f $r.Coverage)
  $summary += ("            golden model: {0}" -f $r.Golden)
  if ($r.TB -notmatch 'PASSED' -or $r.Golden -notmatch '^PASS' -or $r.Coverage -notmatch 'states 9/9, arcs 24/24') {
    $allPass = $false
  }
}

# ---- 3. Mutants (PLAN 4.4): each must be caught -------------------------------
# Edits are regex replacements; the script stops if a pattern is not found, so a
# mutant can never silently become the original design.
$mutants = @(
  @{ Id = "M1"; File = "rtl\traffic_fsm.sv"; Expect = "a_yel";
     What = "emergency in a green goes straight to EMERGENCY (no yellow)";
     Edits = @(, @('if \(emg\)(\s+)next_state = NS_Y;', 'if (emg)$1next_state = EMERGENCY;')) },
  @{ Id = "M2"; File = "rtl\sync_debounce.sv"; Expect = "T11";
     What = "debouncer with 2 samples instead of 3";
     Edits = @(@('\{sh\[1:0\], s2\} == 3''b111', '{sh[0], s2} == 2''b11'),
               @('\{sh\[1:0\], s2\} == 3''b000', '{sh[0], s2} == 2''b00')) },
  @{ Id = "M3"; File = "rtl\traffic_fsm.sv"; Expect = "golden";
     What = "pedestrian request not latched";
     Edits = @(@('else if \(ped_pulse && state != PED_WALK\)', 'else if (1''b1)'),
               @('ped_req <= 1''b1;', 'ped_req <= ped_pulse && state != PED_WALK;')) },
  @{ Id = "M4"; File = "rtl\traffic_fsm.sv"; Expect = "golden";
     What = "NS_Y goes to EW_G (RED1 skipped)";
     Edits = @(, @('EMERGENCY : RED1;', 'EMERGENCY : EW_G;')) },
  @{ Id = "M5"; File = "rtl\traffic_fsm.sv"; Expect = "a_safe";
     What = "EW forced green together with NS_G";
     Edits = @(, @('NS_G:(\s+)light_ns <= L_G;', 'NS_G:$1begin light_ns <= L_G; light_ew <= L_G; end')) },
  @{ Id = "M6"; File = "rtl\traffic_top.sv"; Expect = "a_ylen";
     What = "clk_divider not restarted at a phase change";
     Edits = @(, @('\.restart \(load\)', '.restart (1''b0)')) }
)

Write-Host "`n==== mutants (seed $($seeds[0])) ====" -ForegroundColor Cyan
$summary += ""
$summary += "Mutants (seed $($seeds[0])), each must be caught:"
$allCaught = $true
foreach ($m in $mutants) {
  $dir = "build\mutants\$($m.Id)"
  New-Item -ItemType Directory -Force $dir, "$dir\legacy" | Out-Null
  $text = Get-Content -Raw $m.File
  foreach ($e in $m.Edits) {
    if ($text -notmatch $e[0]) { throw "$($m.Id): pattern not found in $($m.File): $($e[0])" }
    $text = $text -replace $e[0], $e[1]
  }
  $mutFile = Join-Path $dir (Split-Path $m.File -Leaf)
  Set-Content -Encoding ascii $mutFile $text
  $msrc = ($rtl + $bench) | ForEach-Object { if ($_ -eq $m.File) { $mutFile } else { $_ } }
  Compile "$dir\sim" (Resolve-Sources $msrc "$dir\legacy")
  $r = Invoke-Run "$dir\sim" $seeds[0] "$($m.Id)_seed$($seeds[0])" "logs\mutant_$($m.Id).log" "logs\golden_$($m.Id).log"
  $caught = ($r.TB -match 'FAILED') -or ($r.Golden -match '^FAIL')
  if (-not $caught) { $allCaught = $false }
  $tbShort = if ($r.TB -match 'FAILED : .*?, (\d+) errors, (\d+) checker') { "TB FAILED ($($Matches[1]) directed errors, $($Matches[2]) checker violations)" } else { "TB passed" }
  $line = "{0}  {1,-62} {2}; violated: {3}; golden: {4} -> {5} (expected detector: {6})" -f `
          $m.Id, $m.What, $tbShort, $(if ($r.Violated) { $r.Violated } else { "-" }), $r.Golden,
          $(if ($caught) { "CAUGHT" } else { "NOT CAUGHT" }), $m.Expect
  Write-Host $line
  $summary += $line
}

$summary += ""
$verdict = if ($allPass -and $allCaught) { "ALL PASSED (3 seeds: testbench, golden model, coverage 9/9 + 24/24; 6/6 mutants caught)" } else { "SOMETHING FAILED - see above" }
$summary += $verdict
$summary | Set-Content -Encoding ascii logs\summary.log
Write-Host "`n$verdict" -ForegroundColor $(if ($allPass -and $allCaught) { "Green" } else { "Red" })
exit $(if ($allPass -and $allCaught) { 0 } else { 1 })
