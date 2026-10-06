$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$simulator='D:/FPGA/modelsim_ase/win32aloem'
Push-Location $root
try {
 if(!(Test-Path 'sim/work')){& "$simulator/vlib.exe" sim/work}
 & "$simulator/vlog.exe" -work sim/work src/user_source/hdl_source/graded_alert_ctrl.v src/user_source/hdl_source/uart_console.v src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v src/user_source/hdl_source/top_tf_hdmi_audio.v src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v src/user_source/hdl_source/I2S_receiver.v tb/tb_graded_alert_ctrl.v tb/tb_graded_audio.v tb/tb_graded_display.v tb/tb_graded_serial.v tb/tb_uart_console.v tb/tb_emergency_audio.v tb/tb_remote_text.v
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 $checks=@{tb_graded_alert_ctrl='GRADED ALERT CONTROL: ALL CHECKS PASSED';tb_graded_audio='GRADED AUDIO: ALL CHECKS PASSED';tb_graded_display='GRADED DISPLAY: ALL CHECKS PASSED';tb_graded_serial='GRADED SERIAL: ALL CHECKS PASSED';tb_uart_console='UART CONSOLE: ALL CHECKS PASSED';tb_emergency_audio='AUDIO RESULT: ALL CHECKS PASSED';tb_remote_text='REMOTE TEXT: ALL CHECKS PASSED'}
 foreach($name in $checks.Keys){
  $log=Join-Path $root "sim/$name.log"
  & "$simulator/vsim.exe" -c -lib (Join-Path $root 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($checks[$name]) -or $result -match 'Fatal|FAIL:'){throw "$name failed"}
 }
} finally{Pop-Location}
