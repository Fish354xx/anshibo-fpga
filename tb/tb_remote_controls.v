`timescale 1ns/1ps
// 实际串口速率；控制计时缩短，仅验证功能，不用于性能报告。
module tb_remote_controls;
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
wire[1:0] requested_index;
reg busy=0;reg[1:0] shown=0,loading=0;
integer timer=0,request_count=0;
wire [15:0] debug_word={1'b0,3'd4,2'b00,shown,2'b00,loading,1'b1,1'b1,busy,mode};
wire[7:0] settings;
wire keys_next,keys_auto,adjust_active;
wire[2:0] block_reason=mode?2:adjust_active?3:busy?4:0;
uart_console #(.EXTENDED_STATUS(1)) console(
 .clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(block_reason),
 .debug_status(debug_word),.state_code(4'd1),.picture_settings(settings),
 .auto_status(auto_on),.overlay_status(overlay),.next_pulse(remote_next),
 .command_valid(cmd_valid),.command_code(cmd_code),.command_value(cmd_value),
 .overlay_override(ov_valid),.overlay_value(ov_value),.adjust_override(ad_valid),
 .adjust_value(ad_value),.select_override(se_valid),.select_value(se_value),.soft_reset(soft_reset));
picture_key_control #(.CLK_FREQ_HZ(1000000),.DEBOUNCE_MS(1)) keys(
 .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.emergency_mode(mode),
 .adjustment_switch(adjust),.contrast_switch(select),
 .remote_brightness_valid(cmd_valid && cmd_code==5),.remote_contrast_valid(cmd_valid && cmd_code==6),
 .remote_level(cmd_value),.next_press(keys_next),.auto_press(keys_auto),
 .settings_active(adjust_active),.settings(settings));
emergency_mode_ctrl #(.REMOTE_ENABLE(1),.CLK_FREQ_HZ(1000000),.DEBOUNCE_MS(1)) ctrl(
 .clk(clk),.rst(rst),.remote_valid(cmd_valid),.remote_code(cmd_code),.remote_value(cmd_value),
 .auto_play_active(auto_on),.key_mode(key_mode),.key_next_press(keys_next|remote_next),
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
 command("STATUS",6,{"STATUS D=400C S=1 P=12 A=0 O=1 R=0",8'd13,8'd10});
 command("NEXT",4,{"OK NEXT",8'd13,8'd10});check(shown==1,"NEXT advances actual committed index");
 command("SHOW 3",6,{"OK SHOW",8'd13,8'd10});check(shown==2,"SHOW uses one-based image number");
 command("SHOW 1",6,{"OK SHOW",8'd13,8'd10});check(shown==0,"SHOW selects first image");
 command("SHOW 4",6,{"ERR RANGE",8'd13,8'd10});check(shown==0,"invalid image does not load");
 command("AUTO ON",7,{"OK AUTO",8'd13,8'd10});check(auto_on,"AUTO ON sets state");
 command("AUTO ON",7,{"OK AUTO",8'd13,8'd10});check(auto_on,"AUTO ON is idempotent");
 command("SHOW 2",6,{"OK SHOW",8'd13,8'd10});check(!auto_on && shown==1,"SHOW stops auto and selects requested image");
 command("AUTO ON",7,{"OK AUTO",8'd13,8'd10});
 command("AUTO OFF",8,{"OK AUTO",8'd13,8'd10});check(!auto_on,"AUTO OFF clears state");
 command("BRIGHTNESS 4",12,{"OK BRIGHTNESS",8'd13,8'd10});check(settings[5:3]==4,"brightness setter");
 command("BRIGHTNESS +",12,{"OK BRIGHTNESS",8'd13,8'd10});check(settings[5:3]==4,"brightness saturates");
 command("BRIGHTNESS -",12,{"OK BRIGHTNESS",8'd13,8'd10});check(settings[5:3]==3,"brightness decrement");
 command("CONTRAST 0",10,{"OK CONTRAST",8'd13,8'd10});check(settings[2:0]==0,"contrast setter");
 command("CONTRAST -",10,{"OK CONTRAST",8'd13,8'd10});check(settings[2:0]==0,"contrast saturates");
 command("CONTRAST +",10,{"OK CONTRAST",8'd13,8'd10});check(settings[2:0]==1,"contrast increment");
 command("BRIGHTNESS 5",12,{"ERR RANGE",8'd13,8'd10});check(settings[5:3]==3,"invalid parameter rejected");
 command("ADJUST ON",9,{"OK ADJUST",8'd13,8'd10});check(adjust_active && ad_valid,"serial overrides SW2");
 command("NEXT",4,{"ERR ADJUST",8'd13,8'd10});
 command("SELECT CONTRAST",15,{"OK SELECT",8'd13,8'd10});check(settings[6],"serial overrides SW3");
 key_next=0;#30000;key_next=1;#30000;check(settings[2:0]==2,"physical key increments selected contrast");
 command("SELECT BRIGHTNESS",17,{"OK SELECT",8'd13,8'd10});check(!settings[6],"17-byte selector accepted");
 command("ADJUST OFF",10,{"OK ADJUST",8'd13,8'd10});check(!adjust_active,"serial adjustment exit");
 command("OVERLAY OFF",11,{"OK OVERLAY",8'd13,8'd10});check(!overlay,"hide overlay");
 command("OVERLAY ON",10,{"OK OVERLAY",8'd13,8'd10});sw1=0;#100;check(overlay,"remote overlay owner persists");
 command("LOCAL",5,{"OK LOCAL",8'd13,8'd10});check(!overlay && !ov_valid && !ad_valid && !se_valid,"LOCAL returns all switch ownership");
 command("EMERGENCY ON",12,{"OK EMERGENCY",8'd13,8'd10});check(mode && shown==3,"emergency selects fourth picture");
 before_count=request_count;
 command("EMERGENCY ON",12,{"OK EMERGENCY",8'd13,8'd10});check(mode && request_count==before_count,"emergency ON is idempotent");
 command("NEXT",4,{"ERR EMERGENCY",8'd13,8'd10});
 command("CONTRAST 4",10,{"ERR EMERGENCY",8'd13,8'd10});
 command("EMERGENCY OFF",13,{"OK EMERGENCY",8'd13,8'd10});check(!mode && shown==1,"emergency exit restores normal image");
 // 串口和板载应急共用同一状态机。
 key_mode=0;#30000;key_mode=1;#100000;check(mode && shown==3,"physical emergency key retained");
 command("EMERGENCY OFF",13,{"OK EMERGENCY",8'd13,8'd10});check(!mode,"serial exits physical emergency");
 command("RESET",5,{"OK RESET",8'd13,8'd10});
 @(posedge soft_reset);#10000;
 check(!mode && !auto_on && settings==8'h12 && !ov_valid,"RESET after full reply restores defaults");
 command("PING",4,{"PONG",8'd13,8'd10});
 $display("REMOTE CONTROLS: ALL CHECKS PASSED");$finish;
end
initial begin #150000000;$fatal(1,"remote timeout");end
endmodule
