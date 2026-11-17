# =============================================================================
# CE2031 Project 23 - Traffic Light Controller FSM with Emergency Override
# Second simulator: ModelSim-Altera Starter Edition (Quartus II 13.0 SP1).
#
#   .\run_modelsim.ps1
#   .\run_modelsim.ps1 -ModelSim F:\merged_partition_content\altera\modelsim_ase\win32aloem
#
# Compiles the SystemVerilog sources as they are (vlog -sv, no down-conversion),
# including tb\traffic_sva.sv, then runs traffic_tb (+ the SVA bind module) with
# seed 1:
#   logs\modelsim_compile.log   vlog transcript (the SVA must compile cleanly)
#   logs\modelsim_tb.log        vsim transcript: same PASS / coverage lines as
#                               logs\traffic_tb_seed1.log
#   logs\golden_msim_seed1.log  golden model on the ModelSim vectors
# and compares the ModelSim trace with the iverilog one cycle by cycle.
# ModelSim-Altera does not execute concurrent assertions (vsim-8311): the
# results of PLAN 4.2 come from tb\traffic_checker.sv on both simulators.
# =============================================================================
param([string]$ModelSim = "F:\merged_partition_content\altera\modelsim_ase\win32aloem",
      [string]$Python = "python")

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force logs, build, vectors | Out-Null

$vlib = Join-Path $ModelSim "vlib.exe"
$vlog = Join-Path $ModelSim "vlog.exe"
$vsim = Join-Path $ModelSim "vsim.exe"
$lib  = "build\msim_work"

$sources = @("rtl\strobe_gen.sv", "rtl\sync_debounce.sv", "rtl\clk_divider.sv", "rtl\state_timer.sv",
             "rtl\traffic_fsm.sv", "rtl\bin2bcd8.sv", "rtl\traffic_top.sv",
             "tb\traffic_checker.sv", "tb\traffic_sva.sv", "tb\traffic_tb.sv")

if (Test-Path $lib) { Remove-Item -Recurse -Force $lib }
& $vlib $lib | Out-Null
$c = & $vlog -sv -work $lib @sources 2>&1
$c | Set-Content -Encoding ascii logs\modelsim_compile.log
if ($LASTEXITCODE -ne 0) { $c | Write-Host; throw "vlog failed" }
Write-Host "vlog: $(@($c | Select-String -Pattern '\*\* Error').Count) errors, $(@($c | Select-String -Pattern '\*\* Warning').Count) warnings (logs\modelsim_compile.log)"

& $vsim -c -lib $lib -wlf build\vsim.wlf -l logs\modelsim_tb.log traffic_tb traffic_sva_bind `
  +seed=1 +tag=msim_seed1 -do "run -all; quit -f" | Out-Null
if (Test-Path transcript) { Remove-Item transcript }

$log = Get-Content logs\modelsim_tb.log
$log | Select-String -Pattern 'vsim-8311|^# (TRAFFIC TB|COVERAGE|CHECKER VIOLATIONS)' | ForEach-Object { Write-Host $_.Line }

& $Python -I model\golden.py vectors\stim_msim_seed1.txt vectors\rtl_msim_seed1.txt logs\golden_msim_seed1.log | Select-Object -Last 1

# Same stimulus and same trace as iverilog?
$same = $true
foreach ($kind in "stim", "rtl") {
  $a = Get-Content "vectors\${kind}_seed1.txt" | Where-Object { $_ -notmatch '^#' }
  $b = Get-Content "vectors\${kind}_msim_seed1.txt" | Where-Object { $_ -notmatch '^#' }
  if (Compare-Object $a $b -SyncWindow 0 | Select-Object -First 1) { $same = $false }
}
$msg = if ($same) { "ModelSim and iverilog: identical stimulus and output trace (seed 1)" } else { "ModelSim and iverilog traces DIFFER (seed 1)" }
Write-Host $msg -ForegroundColor $(if ($same) { "Green" } else { "Red" })
Add-Content -Encoding ascii logs\modelsim_tb.log "# $msg"
