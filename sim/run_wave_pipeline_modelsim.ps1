$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:\FPGA\modelsim_ase\win32aloem'
    if (!(Test-Path 'sim/work')) {
        & "$simulatorDir\vlib.exe" sim/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & "$simulatorDir\vlog.exe" -work sim/work src/user_source/hdl_source/video_rgb_to_axis_640x480.v src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v src/user_source/hdl_source/I2S_receiver.v tb/tb_audio_wave_pipeline.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/wave_pipeline.log').Replace('\', '/')
    & "$simulatorDir\vsim.exe" -c -lib $libraryPath tb_audio_wave_pipeline -l $logPath -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'WAVE PIPELINE RESULT: ALL CHECKS PASSED' -or $result -match 'FAIL:') {
        throw 'Waveform checks failed; see sim/wave_pipeline.log'
    }
    Write-Host 'PASS: all waveform behavior checks passed'
} finally {
    Pop-Location
}

