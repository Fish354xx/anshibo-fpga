`timescale 1ns/1ps
// 使用真实100MHz、115200参数，以独立串行发送/接收模型验证完整命令。
module tb_uart_transition;
localparam integer BIT_NS=8680;
reg clk=0,rst=1,rx=1;
always #5 clk=~clk;
reg [2:0] block_reason=0;
reg [15:0] debug_status=16'h420C;
reg [3:0] state_code=1;
reg [7:0] settings=8'h12;
wire tx,next_pulse;
wire[1:0] mode;
uart_console #(.TRANSITION_ENABLE(1)) dut(.clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(block_reason),
 .debug_status(debug_status),.state_code(state_code),.picture_settings(settings),.next_pulse(next_pulse),.transition_mode(mode));
wire request;wire[1:0] request_index;
reg button_next=0;
emergency_mode_ctrl #(.CLK_FREQ_HZ(100000000),.DEBOUNCE_MS(20)) ctrl(
 .clk(clk),.rst(rst),.key_mode(1'b1),.key_next_press(next_pulse|button_next),.key_auto_press(1'b0),
 .pause_rotate(1'b0),.scan_done(1'b1),.bmp_ready(1'b1),.first_image_committed(1'b1),
 .display_valid(1'b1),.load_busy(1'b0),.img_found_count(3'd4),.cur_img_idx(2'd0),
 .emergency_mode(),.load_req(request),.load_req_idx(request_index),.load_req_is_emergency(),.disp_commit_en());
integer pulses=0,requests=0,replies=0,errors=0;
reg[255:0] response=0,last_response=0;
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
 response={response[247:0],received};
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
 input integer target;input[255:0] expected;
 begin
  wait(replies>=target);
  if(last_response!==expected)begin errors=errors+1;$display("FAIL response: got %0s expected %0s",last_response,expected);end
  else $display("PASS response: %0s",last_response);
 end
endtask
initial begin
 #100;rst=0;#100;
 line_send("TRANSITION\n",11);expect_reply(1,{"TRANSITION SLIDE",8'd13,8'd10});
 line_send("transition fade\n",16);expect_reply(2,{"OK TRANSITION",8'd13,8'd10});
 if(mode!=2)$fatal(1,"FADE mode wrong");
 line_send("TRANSITION\n",11);expect_reply(3,{"TRANSITION FADE",8'd13,8'd10});
 line_send("TRANSITION CUT\n",15);expect_reply(4,{"OK TRANSITION",8'd13,8'd10});
 line_send("TRANSITION\n",11);expect_reply(5,{"TRANSITION CUT",8'd13,8'd10});
 line_send("TRANSITION BOGUS\n",17);expect_reply(6,{"ERR CMD",8'd13,8'd10});
 if(mode!=0)$fatal(1,"invalid mode changed setting");
 line_send("TRANSITION SLIDE\n",17);expect_reply(7,{"OK TRANSITION",8'd13,8'd10});
 if(mode!=1)$fatal(1,"SLIDE mode wrong");
 rst=1;#100;rst=0;#100;
 line_send("TRANSITION\n",11);expect_reply(8,{"TRANSITION SLIDE",8'd13,8'd10});
 if(errors)$fatal(1,"UART transition errors=%0d",errors);
 $display("UART TRANSITION: ALL CHECKS PASSED");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
