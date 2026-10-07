`timescale 1ns/1ps
module tb_resource_controller;
reg clk=0,rst=1,valid=0,next=0,busy=0;
reg[3:0]code=0;reg[5:0]value=0;reg[4:0]shown=0;
wire request,mode,permit;wire[4:0]target;wire[5:0]hold_seconds;
always #5 clk=~clk;
emergency_mode_ctrl #(.RESOURCE_ENABLE(1),.REMOTE_ENABLE(1),.INDEX_BITS(5),.CLK_FREQ_HZ(1000),
 .EMERGENCY_INDEX(5'd16),.EMERGENCY_MIN_IMAGES(6'd1),.NORMAL_ROTATE_COUNT(6'd16)) dut(
 .clk(clk),.rst(rst),.remote_valid(valid),.remote_code(code),.remote_value(value),
 .key_mode(1'b1),.key_next_press(next),.key_auto_press(1'b0),.pause_rotate(1'b0),
 .scan_done(1'b1),.bmp_ready(1'b1),.first_image_committed(1'b1),.display_valid(1'b1),
 .load_busy(busy),.img_found_count(6'd17),.cur_img_idx(shown),.resource_count(5'd16),
 .resource_hold_seconds(6'd3),.hold_seconds(hold_seconds),.emergency_mode(mode),
 .load_req(request),.load_req_idx(target),.load_req_is_emergency(),.disp_commit_en(permit));
integer requests=0,errors=0;reg[4:0]last;
always @(posedge clk)if(request)begin requests=requests+1;last=target;end
task command;input[3:0]op;input[5:0]arg;begin
 code=op;value=arg;valid=1;@(negedge clk);valid=0;repeat(4)@(negedge clk);
end endtask
task check;input good;input[511:0]msg;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",msg);end
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;busy=1;repeat(5)@(negedge clk);busy=0;
 command(3,1);repeat(2990)@(negedge clk);check(requests==0,"dwell not treated as one second");
 wait(requests==1);check(last==1&&hold_seconds==3,"configured three-second dwell selects next image");
 command(3,0);command(2,15);check(last==15,"SHOW supports image sixteen");shown=15;
 next=1;@(negedge clk);next=0;repeat(4)@(negedge clk);check(last==0,"sixteen-image wrap");
 command(2,15);shown=15;repeat(4)@(negedge clk);
 command(4,1);check(mode&&last==16,"independent emergency slot");shown=16;
 command(4,0);check(!mode&&last==15,"emergency restores full-width saved index");
 if(errors)$fatal(1,"RESOURCE CONTROL errors=%0d",errors);
 $display("RESOURCE CONTROL: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
