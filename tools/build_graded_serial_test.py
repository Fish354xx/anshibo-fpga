"""Build the integration fixture from the existing mocked frame loader bench."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'tb/tb_remote_controls.v').read_text(encoding='utf-8-sig')
s=s.replace('module tb_remote_controls;', 'module tb_graded_serial;')
s=s.replace('wire mode,auto_on,request,permit;', '''wire mode,auto_on,request,permit;
wire[1:0]local_level,remote_level,effective,candidate;
wire selecting,backend_next,major_valid,major_value;
wire routed_valid=major_valid||(cmd_valid&&cmd_code!=4&&cmd_code!=13);
wire[3:0]routed_code=major_valid?4'd4:cmd_code;
wire[2:0]routed_value=major_valid?{2'b0,major_value}:cmd_value;
graded_alert_ctrl #(.DEBOUNCE_CYCLES(10),.LONG_CYCLES(1000),.SELECT_TIMEOUT(1000000)) alert(
 .clk(clk),.rst(rst),.key_mode(key_mode),.key_next(key_next),.ready(1'b1),.major_available(1'b1),
 .command_valid(cmd_valid),.command_code(cmd_code),.command_value(cmd_value),.backend_major(mode),
 .local_level(local_level),.remote_level(remote_level),.effective_level(effective),.selecting(selecting),
 .candidate(candidate),.backend_next_key(backend_next),.major_command_valid(major_valid),.major_command_value(major_value));''')
s=s.replace('uart_console #(.EXTENDED_STATUS(1))', 'uart_console #(.EXTENDED_STATUS(1),.GRADED_ALERT_ENABLE(1))')
s=s.replace('.auto_status(auto_on),.overlay_status(overlay)',
 '.effective_alert(effective),.local_alert(local_level),.remote_alert(remote_level),.auto_status(auto_on),.overlay_status(overlay)')
s=s.replace('.key_next(key_next),.key_auto(key_auto),.emergency_mode(mode)',
 '.key_next(backend_next),.key_auto(key_auto),.emergency_mode(mode)')
s=s.replace('.remote_valid(cmd_valid),.remote_code(cmd_code),.remote_value(cmd_value)',
 '.remote_valid(routed_valid),.remote_code(routed_code),.remote_value(routed_value)')
s=s.replace('.key_mode(key_mode),.key_next_press', '.key_mode(1\'b1),.key_next_press')
start=s.index('integer before_count;')
s=s[:start]+'''integer before_count;
initial begin
 #100;base_reset=0;#20000;
 command("PING",4,{"PONG",8'd13,8'd10});
 command("ALERT 1",7,{"OK ALERT",8'd13,8'd10});check(effective==1&&!mode,"reminder normal backend");
 command("NEXT",4,{"OK NEXT",8'd13,8'd10});check(shown==1,"reminder allows daily picture switch");
 command("AUTO ON",7,{"OK AUTO",8'd13,8'd10});
 command("ALERT 2",7,{"OK ALERT",8'd13,8'd10});check(effective==2&&mode&&shown==3,"warning loads emergency picture");
 command("STATUS",6,{"STATUS D=433D S=1 P=12 A=1 O=1 R=0 E=2 B=0 M=2",8'd13,8'd10});
 command("NEXT",4,{"ERR EMERGENCY",8'd13,8'd10});
 before_count=request_count;
 command("ALERT 3",7,{"OK ALERT",8'd13,8'd10});check(effective==3&&request_count==before_count,"upgrade without image reload");
 command("ALERT 0",7,{"ERR RANGE",8'd13,8'd10});
 key_mode=0;#20000;key_mode=1;#20000;check(local_level==3&&!selecting,"local long critical");
 command("ALERT CLEAR",11,{"OK CLEAR",8'd13,8'd10});check(effective==3&&remote_level==0,"remote clear preserves local critical");
 command("STATUS",6,{"STATUS D=433D S=1 P=12 A=1 O=1 R=0 E=3 B=3 M=0",8'd13,8'd10});
 command("ALERT 1",7,{"OK ALERT",8'd13,8'd10});check(effective==3&&remote_level==1,"lower remote retained without downgrade");
 // Two short local releases: select clear, then confirm it.
 key_mode=0;#500;key_mode=1;#500;check(selecting&&candidate==0,"local clear selection");
 key_mode=0;#500;key_mode=1;#100000;check(local_level==0&&effective==1&&!mode&&shown==1,"local clear restores saved normal picture");
 command("ALERT CLEAR",11,{"OK CLEAR",8'd13,8'd10});check(effective==0&&auto_on,"clear retains rotation setting");
 command("EMERGENCY ON",12,{"OK EMERGENCY",8'd13,8'd10});check(effective==3&&mode,"legacy command accepted");
 command("EMERGENCY OFF",13,{"OK EMERGENCY",8'd13,8'd10});check(effective==0&&!mode,"legacy clear accepted");
 command("STATUS",6,{"STATUS D=411C S=1 P=12 A=1 O=1 R=0 E=0 B=0 M=0",8'd13,8'd10});
 $display("GRADED SERIAL: ALL CHECKS PASSED");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
'''
(root/'tb/tb_graded_serial.v').write_text(s,encoding='utf-8')
