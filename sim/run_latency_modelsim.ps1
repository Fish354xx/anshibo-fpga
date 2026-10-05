$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:/FPGA/modelsim_ase/win32aloem'
    New-Item -ItemType Directory -Force measurements | Out-Null
    if (!(Test-Path 'sim/work')) { & "$simulatorDir/vlib.exe" sim/work }
    & "$simulatorDir/vlog.exe" -work sim/work '+incdir+src/user_source/hdl_source/SD' src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/top_tf_hdmi_audio.v src/user_source/hdl_source/SD/color_bar.v src/user_source/hdl_source/SD/video_timing_data.v tb/tb_latency_measurement.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'measurements/latency.log').Replace('\', '/')
    & "$simulatorDir/vsim.exe" -c -lib $libraryPath tb_latency_measurement -l $logPath -do 'run -all; quit -f'
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'LATENCY: ALL CHECKS PASSED' -or $result -match 'Fatal|FAIL:') { throw 'Timing measurement failed' }
} finally { Pop-Location }
