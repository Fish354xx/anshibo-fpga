`timescale 1ns/1ps
// 使用真实100MHz、115200参数，以独立串行发送/接收模型验证完整命令。
module tb_uart_console;
localparam integer BIT_NS=8680;
reg clk=0,rst=1,rx=1;
always #5 clk=~clk;
reg [2:0] block_reason=0;
reg [15:0] debug_status=16'h420C;
reg [3:0] state_code=1;
reg [7:0] settings=8'h12;
wire tx,next_pulse;
uart_console dut(.clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(block_reason),
 .debug_status(debug_status),.state_code(state_code),.picture_settings(settings),.next_pulse(next_pulse));
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
integer n,before_pulses;
initial begin
 #100;rst=0;#100;
 // 起始位毛刺不应被识别为字符。
 rx=0;#20;rx=1;#(BIT_NS*2);
 line_send("PING\n",5);expect_reply(1,{"PONG",8'd13,8'd10});
 line_send({"next",8'd13,8'd10},6);expect_reply(2,{"OK NEXT",8'd13,8'd10});#(BIT_NS*2);
 if(pulses!=1 || requests!=1)$fatal(1,"CRLF duplicate or control integration failure");
 // 快照在STATUS收到时保存，随后输入变化不应污染本条应答。
 line_send("STATUS\n",7);#(BIT_NS);debug_status=16'h1234;state_code=7;settings=8'hAB;
 expect_reply(3,{"STATUS D=420C S=1 P=12",8'd13,8'd10});
 line_send({"STATUS",8'd13},7);expect_reply(4,{"STATUS D=1234 S=7 P=AB",8'd13,8'd10});
 before_pulses=pulses;
 for(n=1;n<=5;n=n+1)begin
  block_reason=n;line_send("NEXT\n",5);
  case(n)
   1:expect_reply(4+n,{"ERR NOTREADY",8'd13,8'd10});
   2:expect_reply(4+n,{"ERR EMERGENCY",8'd13,8'd10});
   3:expect_reply(4+n,{"ERR ADJUST",8'd13,8'd10});
   4:expect_reply(4+n,{"ERR BUSY",8'd13,8'd10});
   5:expect_reply(4+n,{"ERR NOIMAGE",8'd13,8'd10});
  endcase
 end
 if(pulses!=before_pulses)$fatal(1,"blocked command executed");
 block_reason=0;
 line_send("BOGUS\n",6);expect_reply(10,{"ERR CMD",8'd13,8'd10});
 repeat(33)byte_send("A",0);byte_send(10,0);expect_reply(11,{"ERR LINE",8'd13,8'd10});
 byte_send("N",1);line_send("EXT\n",4);expect_reply(12,{"ERR LINE",8'd13,8'd10});
 line_send("NEXT\n",5);expect_reply(13,{"OK NEXT",8'd13,8'd10});
 // 在长状态应答期间到达的新指令必须被拒绝，不能悄悄执行。
 line_send("STATUS\n",7);line_send("NEXT\n",5);
 expect_reply(14,{"STATUS D=1234 S=7 P=AB",8'd13,8'd10});
 expect_reply(15,{"ERR BUSY",8'd13,8'd10});
 if(pulses!=before_pulses+1)$fatal(1,"busy command executed");
 // 复位丢弃半条命令。
 line_send("NE",2);#100;rst=1;#100;rst=0;
 line_send("XT\n",3);expect_reply(16,{"ERR CMD",8'd13,8'd10});
 line_send("NEXT\n",5);expect_reply(17,{"OK NEXT",8'd13,8'd10});
 // 板载控制器输入仍可独立发出下一张请求。
 @(negedge clk);button_next=1;@(negedge clk);button_next=0;repeat(10)@(negedge clk);
 if(requests!=pulses+1)$fatal(1,"board operation lost");
 if(errors)$fatal(1,"UART response errors=%0d",errors);
 $display("UART CONSOLE: ALL CHECKS PASSED");$finish;
end
initial begin #50000000;$fatal(1,"UART timeout");end
endmodule
