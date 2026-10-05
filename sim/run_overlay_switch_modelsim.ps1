$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:\FPGA\modelsim_ase\win32aloem'
    if (!(Test-Path 'sim/work')) {
        & "$simulatorDir\vlib.exe" sim/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & "$simulatorDir\vlog.exe" -work sim/work src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb/tb_overlay_switch.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/overlay_switch.log').Replace('\', '/')
    & "$simulatorDir\vsim.exe" -c -lib $libraryPath tb_overlay_switch -l $logPath -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'OVERLAY SWITCH: ALL CHECKS PASSED' -or $result -match 'FAIL:') {
        throw 'Overlay switch checks failed; see sim/overlay_switch.log'
    }
    Write-Host 'PASS: all overlay switch checks passed'
} finally {
    Pop-Location
}

