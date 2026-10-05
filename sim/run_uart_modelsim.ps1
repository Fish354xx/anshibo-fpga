$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $simulatorDir = 'D:/FPGA/modelsim_ase/win32aloem'
    if (!(Test-Path 'sim/work')) { & "$simulatorDir/vlib.exe" sim/work }
    & "$simulatorDir/vlog.exe" -work sim/work src/user_source/hdl_source/uart_console.v src/user_source/hdl_source/SD/sd_card_bmp.v tb/tb_uart_console.v
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $libraryPath = (Join-Path $projectRoot 'sim/work').Replace('\', '/')
    $logPath = (Join-Path $projectRoot 'sim/uart_console.log').Replace('\', '/')
    & "$simulatorDir/vsim.exe" -c -lib $libraryPath tb_uart_console -l $logPath -do 'run -all; quit -f'
    $result = Get-Content -LiteralPath $logPath -Raw
    if ($LASTEXITCODE -ne 0 -or $result -notmatch 'UART CONSOLE: ALL CHECKS PASSED' -or $result -match 'Fatal|FAIL:') {
        throw 'UART tests failed'
    }
} finally { Pop-Location }
