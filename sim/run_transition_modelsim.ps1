$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$simulator='D:/FPGA/modelsim_ase/win32aloem'
Push-Location $root
try {
 if(!(Test-Path 'sim/work')){& "$simulator/vlib.exe" sim/work}
 & "$simulator/vlog.exe" -work sim/work src/user_source/hdl_source/event_packet_buffer.v src/user_source/hdl_source/uart_console.v src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/SD/frame_fifo_read.v src/user_source/hdl_source/SD/bmp_read.v src/user_source/hdl_source/SD/sd_card_top.v src/user_source/hdl_source/SD/sd_card_sec_read_write.v src/user_source/hdl_source/SD/sd_card_cmd.v src/user_source/hdl_source/SD/spi_master.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb/tb_picture_transition.v tb/tb_slide_transition.v tb/tb_slide_reader.v tb/tb_push_reader.v tb/tb_push_no_black.v tb/tb_push_retire.v tb/tb_uart_transition.v
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 $checks=@{tb_picture_transition='TRANSITION RESULT: ALL CHECKS PASSED';tb_slide_transition='SLIDE CONTROL: ALL CHECKS PASSED';tb_slide_reader='SLIDE READER: ALL CHECKS PASSED';tb_push_reader='PUSH READER: ALL CHECKS PASSED';tb_push_no_black='PUSH NO BLACK: ALL CHECKS PASSED';tb_push_retire='PUSH RETIRE: ALL CHECKS PASSED';tb_uart_transition='UART TRANSITION: ALL CHECKS PASSED'}
 foreach($name in $checks.Keys){
  $log=Join-Path $root "sim/$name.log"
  & "$simulator/vsim.exe" -c -lib (Join-Path $root 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($checks[$name]) -or $result -match '(?m)^#\s*(FAIL\b|\*\* Fatal)'){throw "$name failed"}
 }
} finally{Pop-Location}
