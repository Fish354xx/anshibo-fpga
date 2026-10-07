param(
 [string]$Simulator='D:/FPGA/modelsim_ase/win32aloem',
 [string]$PythonPath=(Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 if(!(Test-Path 'sim/work')){& "$Simulator/vlib.exe" sim/work;if($LASTEXITCODE -ne 0){throw 'vlib failed'}}
 $sources=@('src/user_source/hdl_source/SD/fat32_resources.v','src/user_source/hdl_source/SD/bmp_read.v','src/user_source/hdl_source/SD/sd_card_bmp.v','src/user_source/hdl_source/SD/sd_card_top.v','src/user_source/hdl_source/SD/sd_card_cmd.v','src/user_source/hdl_source/SD/sd_card_sec_read_write.v','src/user_source/hdl_source/SD/spi_master.v','src/user_source/hdl_source/uart_console.v','src/user_source/hdl_source/graded_alert_ctrl.v','src/user_source/hdl_source/event_packet_buffer.v','src/user_source/hdl_source/video_rgb_to_axis_640x480.v','tb/tb_fat_resources.v','tb/tb_fat_variants.v','tb/tb_resource_controller.v','tb/tb_resource_pipeline.v','tb/tb_uart_resources.v','tb/tb_remote_controls.v','tb/tb_event_serial.v','tb/tb_event_display.v','tb/tb_remote_text.v')
 & "$Simulator/vlog.exe" -work sim/work @sources
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 function Invoke-Check([string]$Name,[string]$Marker,[string]$Log,[string]$Variant='') {
  $argsList=@('-c','-lib',(Join-Path $root 'sim/work'),$Name)
  if($Variant){$argsList+=('+VARIANT='+$Variant)}
  $argsList+=@('-l',$Log,'-do','run -all; quit -f')
  & "$Simulator/vsim.exe" @argsList
  $result=Get-Content $Log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($Marker) -or $result -match '(?m)^#\s*(FAIL\b|\*\* Fatal)'){throw "$Name failed"}
 }
 & $PythonPath tools/build_fat_fixture.py
 if($LASTEXITCODE -ne 0){throw 'Fixture failed'}
 Invoke-Check tb_fat_resources 'FAT RESOURCE: ALL CHECKS PASSED' sim/fat_resources.log
 Invoke-Check tb_resource_controller 'RESOURCE CONTROL: ALL CHECKS PASSED' sim/resource_controller.log
 Invoke-Check tb_uart_resources 'RESOURCE UART: ALL CHECKS PASSED' sim/uart_resources.log
 Invoke-Check tb_resource_pipeline 'RESOURCE PIPELINE: ALL CHECKS PASSED' sim/resource_pipeline.log
 foreach($variant in @('limits','bom','superfloppy','invalid')) {
  & $PythonPath tools/build_fat_fixture.py --variant $variant
  if($LASTEXITCODE -ne 0){throw 'Fixture failed'}
  Invoke-Check tb_fat_variants 'FAT VARIANTS: ALL CHECKS PASSED' "sim/fat_$variant.log" $variant
 }
 & $PythonPath tools/build_fat_fixture.py
 foreach($variant in @('no_card','short','timeout')) {
  Invoke-Check tb_fat_variants 'FAT VARIANTS: ALL CHECKS PASSED' "sim/fat_$variant.log" $variant
 }
 foreach($check in @(
  @('tb_remote_controls','REMOTE CONTROLS: ALL CHECKS PASSED','remote_controls_resources'),
  @('tb_event_serial','EVENT SERIAL: ALL CHECKS PASSED','event_serial_resources'),
  @('tb_event_display','EVENT DISPLAY: ALL CHECKS PASSED','event_display_resources'),
  @('tb_remote_text','REMOTE TEXT: ALL CHECKS PASSED','remote_text_resources'))) {
  Invoke-Check $check[0] $check[1] "sim/$($check[2]).log"
 }
} finally {
 & $PythonPath tools/build_fat_fixture.py
 Pop-Location
}
