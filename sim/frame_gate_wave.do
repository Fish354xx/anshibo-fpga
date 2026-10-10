onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_latency_frame_measure/vclk
add wave -noupdate /tb_latency_frame_measure/gmode
add wave -noupdate /tb_latency_frame_measure/loaded
add wave -noupdate /tb_latency_frame_measure/active
add wave -noupdate /tb_latency_frame_measure/vs
add wave -noupdate /tb_latency_frame_measure/de
add wave -noupdate /tb_latency_frame_measure/audio
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1414740000 ps} 0} {{Cursor 2} {240000 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 220
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ms
update
WaveRestoreZoom {0 ps} {2 ms}
