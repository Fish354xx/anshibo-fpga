# Execute from src/td_project via td_commands_prompt.exe ../../tools/build_td.tcl
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run ./anshibo.al
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
optimize_rtl
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
optimize_gate
legalize_phy_inst
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
place
route
update_timing -mode final
report_timing_summary -file ./clean_timing.rpt
report_area -file ./clean_area.rpt
bitgen -bit ./anshibo_clean.bit
close_project
puts "CLEAN_PACKAGE_BUILD_FINISHED"
