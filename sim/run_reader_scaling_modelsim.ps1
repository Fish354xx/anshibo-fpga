$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:\FPGA\modelsim_ase\win32aloem'
    if (!(Test-Path 'sim/work')) {
        & "$simulatorDir\vlib.exe" sim/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & "$simulatorDir\vlog.exe" -work sim/work src/user_source/hdl_source/SD/bmp_read.v tb/tb_bmp_reader_scaling.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/reader_scaling.log').Replace('\', '/')
    & "$simulatorDir\vsim.exe" -c -lib $libraryPath tb_bmp_reader_scaling -l $logPath -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($result -notmatch 'READER RESULT: ALL CHECKS PASSED' -or $result -match 'FAIL:') {
        throw 'BMP reader scaling checks failed; see sim/reader_scaling.log'
    }
    Write-Host 'PASS: all BMP reader scaling behavior checks passed'
} finally {
    Pop-Location
}


