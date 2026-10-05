$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simulatorDir='D:/FPGA/modelsim_ase/win32aloem'
Push-Location $projectRoot
try {
 if(!(Test-Path 'sim/work')) { & "$simulatorDir/vlib.exe" sim/work }
 & "$simulatorDir/vlog.exe" -work sim/work src/user_source/hdl_source/uart_console.v src/user_source/hdl_source/SD/sd_card_bmp.v src/user_source/hdl_source/top_tf_hdmi_audio.v src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb/tb_remote_text.v tb/tb_remote_controls.v tb/tb_uart_console.v tb/tb_emergency_mode_ctrl.v tb/tb_reset_domains.v
 if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
 $checks=@{tb_remote_text='REMOTE TEXT: ALL CHECKS PASSED';tb_remote_controls='REMOTE CONTROLS: ALL CHECKS PASSED';tb_uart_console='UART CONSOLE: ALL CHECKS PASSED';tb_emergency_mode_ctrl='SIM RESULT: ALL CHECKS PASSED';tb_reset_domains='RESET DOMAINS: ALL CHECKS PASSED'}
 foreach($name in $checks.Keys){
  $log=(Join-Path $projectRoot "sim/$name.log").Replace('\','/')
  & "$simulatorDir/vsim.exe" -c -lib (Join-Path $projectRoot 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -ne 0 -or !$result.Contains($checks[$name]) -or $result -match 'Fatal|FAIL:|FAIL=[1-9]'){throw "$name failed"}
 }
} finally {Pop-Location}

