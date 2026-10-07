`timescale 1ns/1ps
// 使用真实100MHz、115200参数，以独立串行发送/接收模型验证完整命令。
module tb_uart_resources;
localparam integer BIT_NS=8680;
reg clk=0,rst=1,rx=1;
always #5 clk=~clk;
reg [2:0] block_reason=0;
reg [15:0] debug_status=16'h420C;
reg [3:0] state_code=1;
reg [7:0] settings=8'h12;
wire tx,next_pulse;
reg[4:0]n=16,p=16;reg[2:0]reason=0;wire[4:0]value;wire valid;
uart_console #(.RESOURCE_ENABLE(1)) dut(.clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(reason),
 .debug_status(debug_status),.state_code(state_code),.picture_settings(settings),.next_pulse(next_pulse),.command_valid(valid),.command_value(value),
 .resource_normal_count(n),.resource_active_count(p),.resource_index(5'd15),
 .resource_seconds(6'd60),.resource_flags(8'd0),.resource_ready(1'b1),.resource_emergency_file(1'b1));
wire request;wire[1:0] request_index;
reg button_next=0;
emergency_mode_ctrl #(.CLK_FREQ_HZ(100000000),.DEBOUNCE_MS(20)) ctrl(
 .clk(clk),.rst(rst),.key_mode(1'b1),.key_next_press(next_pulse|button_next),.key_auto_press(1'b0),
 .pause_rotate(1'b0),.scan_done(1'b1),.bmp_ready(1'b1),.first_image_committed(1'b1),
 .display_valid(1'b1),.load_busy(1'b0),.img_found_count(3'd4),.cur_img_idx(2'd0),
 .emergency_mode(),.load_req(request),.load_req_idx(request_index),.load_req_is_emergency(),.disp_commit_en());
integer pulses=0,requests=0,replies=0,errors=0;
reg[511:0] response=0,last_response=0;
reg[7:0] received;
integer bit_n;
always @(posedge clk) begin
 if(next_pulse)pulses=pulses+1;
 if(request)begin requests=requests+1;if(request_index!=1)$fatal(1,"wrong next image index");end
end
// 独立解码TX：起始沿后1.5位处读第0位，逐位采样并验证停止位。
initial forever begin
 @(negedge tx);#(BIT_NS+BIT_NS/2);
 for(bit_n=0;bit_n<8;bit_n=bit_n+1)begin received[bit_n]=tx;#(BIT_NS);end
 if(tx!==1'b1)$fatal(1,"TX stop bit invalid");
 response={response[503:0],received};
 if(received==10)begin last_response=response;response=0;replies=replies+1;end
end
task byte_send;
 input[7:0] value;input bad_stop;
 integer b;
 begin
  rx=0;#(BIT_NS);
  for(b=0;b<8;b=b+1)begin rx=value[b];#(BIT_NS);end
  rx=!bad_stop;#(BIT_NS);rx=1;#100;
 end
endtask
task line_send;
 input[255:0] value;input integer length;
 integer k;
 begin for(k=length-1;k>=0;k=k-1)byte_send(value[k*8+:8],0);end
endtask
task expect_reply;
 input integer target;input[511:0] expected;
 begin
  wait(replies>=target);
  if(last_response!==expected)begin errors=errors+1;$display("FAIL response: got %0s expected %0s",last_response,expected);end
  else $display("PASS response: %0s",last_response);
 end
endtask
initial begin
 #100;rst=0;#100;
 line_send("RESOURCES\n",10);expect_reply(1,{"RES N=10 P=10 E=1 F=00 I=0F T=3C R=1",8'd13,8'd10});
 line_send("SHOW 16\n",8);expect_reply(2,{"OK SHOW",8'd13,8'd10});
 if(value!=15)$fatal(1,"SHOW 16 truncated index");
 line_send("SHOW 9\n",7);expect_reply(3,{"OK SHOW",8'd13,8'd10});
 if(value!=8)$fatal(1,"SHOW 9 wrong index");
 line_send("SHOW 17\n",8);expect_reply(4,{"ERR RANGE",8'd13,8'd10});
 line_send("SHOW 0\n",7);expect_reply(5,{"ERR RANGE",8'd13,8'd10});
 n=1;p=1;reason=5;
 line_send("SHOW 1\n",7);expect_reply(6,{"OK SHOW",8'd13,8'd10});
 line_send("AUTO ON\n",8);expect_reply(7,{"ERR NOIMAGE",8'd13,8'd10});
 line_send("SHOW 2\n",7);expect_reply(8,{"ERR NOIMAGE",8'd13,8'd10});
 if(errors)$fatal(1,"RESOURCE UART errors=%0d",errors);
 $display("RESOURCE UART: ALL CHECKS PASSED");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
