param([string]$Simulator='D:/FPGA/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 if(!(Test-Path 'sim/work')){& "$Simulator/vlib.exe" sim/work}
 & "$Simulator/vlog.exe" -work sim/work src/user_source/hdl_source/SD/fat32_resources.v src/user_source/hdl_source/SD/bmp_read.v src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/SD/sd_card_top.v src/user_source/hdl_source/SD/sd_card_cmd.v src/user_source/hdl_source/SD/sd_card_sec_read_write.v src/user_source/hdl_source/SD/spi_master.v tb/tb_prefetch_scheduler.v tb/tb_prefetch_pipeline.v
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 $pythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
 & $pythonPath tools/build_fat_fixture.py
 if($LASTEXITCODE -ne 0){throw 'Fixture failed'}
 $checks=@{tb_prefetch_scheduler='PREFETCH SCHEDULER: ALL CHECKS PASSED';tb_prefetch_pipeline='PREFETCH PIPELINE: ALL CHECKS PASSED'}
 foreach($name in $checks.Keys){
  $log=Join-Path $root "sim/$name.log"
  & "$Simulator/vsim.exe" -c -lib (Join-Path $root 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($checks[$name]) -or $result -match '(?m)^#\s*(FAIL\b|\*\* Fatal)'){throw "$name failed"}
 }
} finally {Pop-Location}
