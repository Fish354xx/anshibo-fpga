`timescale 1ns/1ps
// 实际串口速率；控制计时缩短，仅验证功能，不用于性能报告。
module tb_graded_serial;
localparam integer BIT_NS=8680;
reg clk=0,base_reset=1,rx=1;
always #5 clk=~clk;
wire tx,remote_next,cmd_valid,soft_reset;
wire [3:0] cmd_code;wire[2:0] cmd_value;
wire ov_valid,ov_value,ad_valid,ad_value,se_valid,se_value;
reg sw1=1,sw2=0,sw3=0,key_next=1,key_auto=1,key_mode=1;
wire overlay=ov_valid?ov_value:sw1;
wire adjust=ad_valid?ad_value:sw2;
wire select=se_valid?se_value:sw3;
reg [7:0] reset_hold=0;
always @(posedge clk or posedge base_reset)begin
 if(base_reset)reset_hold<=0;
 else if(soft_reset)reset_hold<=255;
 else if(reset_hold!=0)reset_hold<=reset_hold-1'b1;
end
wire rst=base_reset || reset_hold!=0;
wire mode,auto_on,request,permit;
wire[1:0]local_level,remote_level,effective,candidate;
wire selecting,backend_next,major_valid,major_value;
wire routed_valid=major_valid||(cmd_valid&&cmd_code!=4&&cmd_code!=13);
wire[3:0]routed_code=major_valid?4'd4:cmd_code;
wire[2:0]routed_value=major_valid?{2'b0,major_value}:cmd_value;
graded_alert_ctrl #(.DEBOUNCE_CYCLES(10),.LONG_CYCLES(1000),.SELECT_TIMEOUT(1000000)) alert(
 .clk(clk),.rst(rst),.key_mode(key_mode),.key_next(key_next),.ready(1'b1),.major_available(1'b1),
 .command_valid(cmd_valid),.command_code(cmd_code),.command_value(cmd_value),.backend_major(mode),
 .local_level(local_level),.remote_level(remote_level),.effective_level(effective),.selecting(selecting),
 .candidate(candidate),.backend_next_key(backend_next),.major_command_valid(major_valid),.major_command_value(major_value));
wire[1:0] requested_index;
reg busy=0;reg[1:0] shown=0,loading=0;
integer timer=0,request_count=0;
wire [15:0] debug_word={1'b0,3'd4,2'b00,shown,2'b00,loading,1'b1,1'b1,busy,mode};
wire[7:0] settings;
wire keys_next,keys_auto,adjust_active;
wire[2:0] block_reason=mode?2:adjust_active?3:busy?4:0;
uart_console #(.EXTENDED_STATUS(1),.GRADED_ALERT_ENABLE(1)) console(
 .clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(block_reason),
 .debug_status(debug_word),.state_code(4'd1),.picture_settings(settings),
 .effective_alert(effective),.local_alert(local_level),.remote_alert(remote_level),.auto_status(auto_on),.overlay_status(overlay),.next_pulse(remote_next),
 .command_valid(cmd_valid),.command_code(cmd_code),.command_value(cmd_value),
 .overlay_override(ov_valid),.overlay_value(ov_value),.adjust_override(ad_valid),
 .adjust_value(ad_value),.select_override(se_valid),.select_value(se_value),.soft_reset(soft_reset));
picture_key_control #(.CLK_FREQ_HZ(1000000),.DEBOUNCE_MS(1)) keys(
 .clk(clk),.rst(rst),.key_next(backend_next),.key_auto(key_auto),.emergency_mode(mode),
 .adjustment_switch(adjust),.contrast_switch(select),
 .remote_brightness_valid(cmd_valid && cmd_code==5),.remote_contrast_valid(cmd_valid && cmd_code==6),
 .remote_level(cmd_value),.next_press(keys_next),.auto_press(keys_auto),
 .settings_active(adjust_active),.settings(settings));
emergency_mode_ctrl #(.REMOTE_ENABLE(1),.CLK_FREQ_HZ(1000000),.DEBOUNCE_MS(1)) ctrl(
 .clk(clk),.rst(rst),.remote_valid(routed_valid),.remote_code(routed_code),.remote_value(routed_value),
 .auto_play_active(auto_on),.key_mode(1'b1),.key_next_press(keys_next|remote_next),
 .key_auto_press(keys_auto),.pause_rotate(adjust_active),.scan_done(1'b1),.bmp_ready(1'b1),
 .first_image_committed(1'b1),.display_valid(1'b1),.load_busy(busy),.img_found_count(3'd4),
 .cur_img_idx(shown),.emergency_mode(mode),.load_req(request),.load_req_idx(requested_index),
 .load_req_is_emergency(),.disp_commit_en(permit));
// 简化的完整帧加载模型：事务持续50us，受提交许可控制；不模拟真实TF/SDRAM速度。
always @(posedge clk)begin
 if(rst)begin shown<=0;loading<=0;busy<=0;timer<=0;end
 else if(busy)begin
  if(timer==0)begin busy<=0;if(permit)shown<=loading;end else timer<=timer-1;
 end else if(request)begin busy<=1;loading<=requested_index;timer<=4999;request_count=request_count+1;end
end
integer replies=0,errors=0,bit_n;
reg[511:0] response=0,last_response=0;
reg[7:0] received;
initial forever begin
 @(negedge tx);#(BIT_NS+BIT_NS/2);
 for(bit_n=0;bit_n<8;bit_n=bit_n+1)begin received[bit_n]=tx;#(BIT_NS);end
 if(tx!==1)$fatal(1,"TX stop bit");
 response={response[503:0],received};
 if(received==10)begin last_response=response;response=0;replies=replies+1;end
end
task byte_send;input[7:0] c;integer k;
begin rx=0;#(BIT_NS);for(k=0;k<8;k=k+1)begin rx=c[k];#(BIT_NS);end rx=1;#(BIT_NS);#100;end
endtask
task command;
input[511:0] text;input integer length;input[511:0] expected;
integer k,target;
begin
 target=replies+1;
 for(k=length-1;k>=0;k=k-1)byte_send(text[k*8+:8]);
 byte_send(10);wait(replies==target);
 if(last_response!==expected)$fatal(1,"reply mismatch command=%0s got=%0s expected=%0s",text,last_response,expected);
 $display("PASS command: %0s",text);
end endtask
task check;input ok;input[511:0] message;
begin if(ok!==1)$fatal(1,"%0s",message);else $display("PASS state: %0s",message);end
endtask
integer before_count;
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
