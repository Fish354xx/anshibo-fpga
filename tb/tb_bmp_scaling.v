`timescale 1ns/1ps
module tb_bmp_scaling;
reg clk=0,rst=1,start=0,valid=0,ready=1;
reg [10:0] w;reg [9:0] h;
reg [7:0] data;
wire accept,emit,done;wire [23:0] rgb;
always #5 clk=~clk;
bmp_nearest_scaler #(.OUT_WIDTH(8),.OUT_HEIGHT(6)) dut(
 .clk(clk),.rst(rst),.start(start),.src_width(w),.src_height(h),
 .in_valid(valid),.in_byte(data),.in_ready(accept),.out_ready(ready),
 .out_valid(emit),.out_rgb(rgb),.done(done));
integer errors=0,count=0,cycle=0,x,y,k,ex,ey;
function [23:0] pixel;input integer px,py;begin pixel={8'h80,py[7:0],px[7:0]};end endfunction
always @(negedge clk) begin
 cycle=cycle+1;ready=(cycle%7!=0 && cycle%7!=1 && cycle%7!=2);
 if(emit) begin
   ex=(count%8)*w/8;ey=(count/8)*h/6;
   if(rgb!==pixel(ex,ey)) begin errors=errors+1;$display("FAIL pixel %d got %h expected %h",count,rgb,pixel(ex,ey));end
   count=count+1;
 end
end
task byte_send;input [7:0] value;
begin
 @(negedge clk);valid=0;
 while(!accept) @(negedge clk);
 data=value;valid=1;@(negedge clk);valid=0;
end endtask
task image;input integer width,height;
begin
 w=width;h=height;count=0;start=1;@(negedge clk);start=0;
 for(y=0;y<height;y=y+1) begin
  for(x=0;x<width;x=x+1) begin byte_send(x);byte_send(y);byte_send(8'h80);end
  for(k=0;k<(width%4);k=k+1) byte_send(8'hEE);
 end
 wait(done);repeat(3) @(negedge clk);
 if(count!=48) begin errors=errors+1;$display("FAIL output count %d",count);end
 $display("CASE %dx%d -> 8x6, count=%d",width,height,count);
end endtask
initial begin
 repeat(5) @(negedge clk);rst=0;
 image(8,6);image(4,3);image(16,12);image(7,5);image(11,9);image(1,1);image(3,13);image(17,2);
 if(errors) $fatal(1,"SCALING RESULT: %d errors",errors);
 $display("SCALING RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
