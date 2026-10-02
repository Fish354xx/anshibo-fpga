$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:\FPGA\modelsim_ase\win32aloem'
    if (!(Test-Path 'sim/work')) {
        & "$simulatorDir\vlib.exe" sim/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & "$simulatorDir\vlog.exe" -work sim/work src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb/tb_picture_transition.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/transition.log').Replace('\', '/')
    & "$simulatorDir\vsim.exe" -c -lib $libraryPath tb_picture_transition -l $logPath -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'TRANSITION RESULT: ALL CHECKS PASSED' -or $result -match 'FAIL:') {
        throw 'Picture transition checks failed; see sim/transition.log'
    }
    Write-Host 'PASS: all picture transition behavior checks passed'
} finally {
    Pop-Location
}


