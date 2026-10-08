param([string]$Simulator='D:/FPGA/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 New-Item -ItemType Directory -Force measurements/quantitative | Out-Null
 if(!(Test-Path sim/work)){& "$Simulator/vlib.exe" sim/work;if($LASTEXITCODE){throw 'vlib failed'}}
 # Extract the current production gate; do not maintain a separate implementation.
 $top=Get-Content src/user_source/hdl_source/top_tf_hdmi_audio.v -Raw
 $start=$top.IndexOf('module emergency_audio_frame_gate(')
 $end=$top.IndexOf('endmodule',$start)+9
 if($start -lt 0 -or $end -le $start){throw 'Gate extraction failed'}
 [IO.File]::WriteAllText((Join-Path $root 'sim/latency_frame_gate.v'),$top.Substring($start,$end-$start),[Text.UTF8Encoding]::new($false))
 $sources=@('fat32_resources','bmp_read','sd_card_bmp','sd_card_top','sd_card_cmd','sd_card_sec_read_write','spi_master','video_timing_data','color_bar') | ForEach-Object {"src/user_source/hdl_source/SD/$_.v"}
 & "$Simulator/vlog.exe" '+incdir+src/user_source/hdl_source/SD' -work sim/work @sources sim/latency_frame_gate.v tb/tb_latency_prefetch.v tb/tb_latency_frame_measure.v
 if($LASTEXITCODE){throw 'Compilation failed'}
 $checks=@{tb_latency_prefetch=@('prefetch','LATENCY PREFETCH: ALL CHECKS PASSED');tb_latency_frame_measure=@('frame_gate','LATENCY: ALL CHECKS PASSED')}
 foreach($name in $checks.Keys){
  $log="measurements/quantitative/$($checks[$name][0]).log"
  & "$Simulator/vsim.exe" -c -lib (Join-Path $root 'sim/work') $name -l $log -do 'run -all; quit -f'
  $result=Get-Content $log -Raw
  if($LASTEXITCODE -or !$result.Contains($checks[$name][1]) -or $result -match '(?m)^#\s*(FAIL\b|\*\* Fatal)'){throw "$name failed"}
 }
} finally {Pop-Location}
