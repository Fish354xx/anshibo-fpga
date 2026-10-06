"""Serial parser + transaction engine fixture, using actual 115200 bit timing."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'tb/tb_graded_serial.v').read_text(encoding='utf-8-sig')
s=s.replace('module tb_graded_serial;', 'module tb_event_serial;')
needle='wire routed_valid=major_valid||(cmd_valid&&cmd_code!=4&&cmd_code!=13);'
extra='''wire event_cmd_valid,event_busy,event_result_valid,event_apply_valid,event_active_valid;
wire[2:0]event_cmd,event_state;wire[3:0]event_result;
wire[15:0]event_id,event_crc,event_active_id,event_active_crc,event_generation;
wire[1:0]event_level,event_apply_level,event_active_level;
wire[4:0]event_area,event_active_area;wire[6:0]event_body,event_active_body;
wire[9:0]event_glyph;
reg vc=0,event_install=0,event_shown=0;
always #20 vc=~vc;
wire event_pending,event_bank;
event_packet_buffer packet(.clk(clk),.rst(rst),.cmd_valid(event_cmd_valid),.cmd(event_cmd),
 .event_id(event_id),.check_crc(event_crc),.level(event_level),.area_length(event_area),.body_length(event_body),.glyph(event_glyph),
 .ready(1'b1),.major_available(1'b1),.legacy_change(cmd_valid&&(cmd_code==4||cmd_code==13)),.local_level(local_level),
 .result_valid(event_result_valid),.result(event_result),.apply_valid(event_apply_valid),.apply_level(event_apply_level),
 .active_valid(event_active_valid),.active_id(event_active_id),.active_crc(event_active_crc),.active_generation(event_generation),.active_level(event_active_level),
 .active_area_length(event_active_area),.active_body_length(event_active_body),.busy(event_busy),.event_state(event_state),
 .video_clk(vc),.video_rst(rst),.install(event_install),.shown_remote(event_shown),.shown_id(event_active_id),.shown_level(event_active_level),.shown_generation(event_generation),
 .video_pending(event_pending),.pending_bank(event_bank),.read_bank(event_bank),.read_index(7'd0),.read_glyph());
wire[3:0]alert_code=event_apply_valid?4'd13:cmd_code;
wire[2:0]alert_value=event_apply_valid?{1'b0,event_apply_level}:cmd_value;
'''
s=s.replace(needle,extra+needle)
s=s.replace('.command_valid(cmd_valid),.command_code(cmd_code),.command_value(cmd_value),.backend_major(mode)',
 '.command_valid(cmd_valid||event_apply_valid),.command_code(alert_code),.command_value(alert_value),.backend_major(mode)')
s=s.replace('.GRADED_ALERT_ENABLE(1)) console', '.GRADED_ALERT_ENABLE(1),.EVENT_ENABLE(1)) console')
s=s.replace('.effective_alert(effective),.local_alert(local_level),.remote_alert(remote_level),', '''.effective_alert(effective),.local_alert(local_level),.remote_alert(remote_level),
 .event_busy(event_busy),.event_result_valid(event_result_valid),.event_result(event_result),.event_active_valid(event_active_valid),
 .event_active_id(event_active_id),.event_active_crc(event_active_crc),.event_active_level(event_active_level),.event_state(event_state),
 .event_active_area(event_active_area),.event_active_body(event_active_body),.event_cmd_valid(event_cmd_valid),.event_cmd(event_cmd),
 .event_id(event_id),.event_crc(event_crc),.event_level(event_level),.event_area(event_area),.event_body(event_body),.event_glyph(event_glyph),''')
start=s.index('integer before_count;')
s=s[:start]+'''initial begin
 #100;base_reset=0;#20000;
 command("PING",4,{"PONG",8'd13,8'd10});
 command("ESTATUS",7,{"EVENT I=0000 L=0 S=0 C=0000 A=00 T=00 P=0",8'd13,8'd10});
 command("EBEGIN 0001 1 02 03",19,{"OK EBEGIN",8'd13,8'd10});
 command("ECHAR 021",9,{"OK ECHAR",8'd13,8'd10});
 command("ECHAR 022",9,{"OK ECHAR",8'd13,8'd10});
 command("ECHAR 023",9,{"OK ECHAR",8'd13,8'd10});
 command("ECHAR 024",9,{"OK ECHAR",8'd13,8'd10});
 command("ECHAR 025",9,{"OK ECHAR",8'd13,8'd10});
 check(!event_active_valid&&effective==0,"wire upload does not change alert");
 command("ECOMMIT 84BD",12,{"ERR CRC",8'd13,8'd10});
 check(!event_active_valid&&effective==0,"wire CRC failure does not publish");
 command("ECOMMIT 84BC",12,{"OK ACCEPT",8'd13,8'd10});
 check(event_active_id==1&&effective==1&&event_busy,"wire accepted atomically");
 command("ESTATUS",7,{"EVENT I=0001 L=1 S=1 C=84BC A=02 T=03 P=1",8'd13,8'd10});
 command("ALERT 3",7,{"ERR EVENTBUSY",8'd13,8'd10});
 @(negedge vc);event_install=1;@(negedge vc);event_install=0;event_shown=1;#1000;
 command("ESTATUS",7,{"EVENT I=0001 L=1 S=2 C=84BC A=02 T=03 P=0",8'd13,8'd10});
 command("NEXT",4,{"OK NEXT",8'd13,8'd10});
 command("ECLEAR 0002",11,{"ERR ID",8'd13,8'd10});
 command("ECLEAR 0001",11,{"OK ECLEAR",8'd13,8'd10});
 check(!event_active_valid&&effective==0,"wire targeted clear");
 command("EBEGIN 0002 3 20 03",19,{"ERR RANGE",8'd13,8'd10});
 command("EBEGIN 00GG 3 02 03",19,{"ERR RANGE",8'd13,8'd10});
 command("EBEGIN 0002 3 02 03",19,{"OK EBEGIN",8'd13,8'd10});
 command("ECHAR 02G",9,{"ERR RANGE",8'd13,8'd10});
 command("ECHAR 25F",9,{"ERR RANGE",8'd13,8'd10});
 command("ECOMMIT 0000",12,{"ERR LENGTH",8'd13,8'd10});
 command("EABORT",6,{"OK ABORT",8'd13,8'd10});
 command("ALERT 2",7,{"OK ALERT",8'd13,8'd10});check(effective==2&&mode,"legacy graded control retained");
 command("ALERT CLEAR",11,{"OK CLEAR",8'd13,8'd10});
 command("PING",4,{"PONG",8'd13,8'd10});
 $display("EVENT SERIAL: ALL CHECKS PASSED");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
'''
(root/'tb/tb_event_serial.v').write_text(s,encoding='utf-8')

