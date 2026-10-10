onerror {resume}
quietly virtual function -install /tb_latency_prefetch { 12.870} virtual_000001
quietly virtual function -install /tb_latency_prefetch { 12.870} virtual_000002
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_latency_prefetch/valid
add wave -noupdate /tb_latency_prefetch/mode
add wave -noupdate /tb_latency_prefetch/dut/prefetch_transaction
add wave -noupdate /tb_latency_prefetch/dut/load_start_pulse
add wave -noupdate -radix unsigned /tb_latency_prefetch/index
add wave -noupdate /tb_latency_prefetch/loaded
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {15060000 ps} 0} {{Cursor 2} {26855000 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 300
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
configure wave -timelineunits us
update
WaveRestoreZoom {14 us} {28 us}
