$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:\FPGA\modelsim_ase\win32aloem'
    if (!(Test-Path 'sim/work')) {
        & "$simulatorDir\vlib.exe" sim/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & "$simulatorDir\vlog.exe" -work sim/work src/user_source/hdl_source/top_tf_hdmi_audio.v src/user_source/hdl_source/SD/frame_fifo_read.v tb/tb_emergency_frame_audio.v tb/tb_read_frame_tag.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/emergency_frame_audio.log').Replace('\', '/')
    & "$simulatorDir\vsim.exe" -c -lib $libraryPath tb_emergency_frame_audio -l $logPath -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'AUDIO FRAME: ALL CHECKS PASSED' -or $result -match 'FAIL:') {
        throw 'Emergency frame audio checks failed; see sim/emergency_frame_audio.log'
    }
    Write-Host 'PASS: all emergency frame audio checks passed'
} finally {
    Pop-Location
}

