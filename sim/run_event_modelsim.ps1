$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$simulator='D:/FPGA/modelsim_ase/win32aloem'
Push-Location $root
try {
 if(!(Test-Path 'sim/work')){& "$simulator/vlib.exe" sim/work}
 & "$simulator/vlog.exe" -work sim/work src/user_source/hdl_source/event_packet_buffer.v src/user_source/hdl_source/graded_alert_ctrl.v src/user_source/hdl_source/uart_console.v src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb/tb_event_packet.v tb/tb_event_display.v tb/tb_event_serial.v tb/tb_uart_console.v tb/tb_remote_text.v
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 $checks=@{tb_event_packet='EVENT PACKET: ALL CHECKS PASSED';tb_event_display='EVENT DISPLAY: ALL CHECKS PASSED';tb_event_serial='EVENT SERIAL: ALL CHECKS PASSED';tb_uart_console='UART CONSOLE: ALL CHECKS PASSED';tb_remote_text='REMOTE TEXT: ALL CHECKS PASSED'}
 foreach($name in $checks.Keys){
  $log=Join-Path $root "sim/$name.log"
  & "$simulator/vsim.exe" -c -lib (Join-Path $root 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($checks[$name]) -or $result -match 'Fatal|FAIL:'){throw "$name failed"}
 }
} finally{Pop-Location}
