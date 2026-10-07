`timescale 1ns/1ps
// Exercise the production BMP reader with bounded synthetic sector timing.
// This is a throughput model, not a TF card or SDRAM hardware measurement.
module tb_tf_media_budget;
reg clk=0,rst=1,load=0,sd_valid=0,sd_end=0;
reg [7:0] sd_byte=0;
wire request,write_request,output_valid,ready;
wire [31:0] address; wire [23:0] rgb;
integer w,h,length,stride,base,b,pos,x,y,component;
integer count=0,errors=0,cycles=0,begin_cycle,sector_count=0;
always #5 clk=~clk;
always @(posedge clk) cycles=cycles+1;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_resume(1'b0),
 .scan_paused(),.scan_start(1'b0),.scan_start_sector(32'd0),
 .scan_max_sector(32'd131071),.scan_target_count(3'd4),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(load),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(write_request),
 .write_req_ack(write_request),.write_ready(1'b1),.sd_sec_read(request),
 .sd_sec_read_addr(address),.sd_sec_read_data(sd_byte),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .bmp_data_wr_en(output_valid),.bmp_data(rgb));
function [7:0] file_byte;
input integer index;
integer p,c,px,py;
begin
 file_byte=0;
 case(index)
 0:file_byte=8'h42;1:file_byte=8'h4D;
 2:file_byte=length;3:file_byte=length>>8;4:file_byte=length>>16;5:file_byte=length>>24;
 10:file_byte=54;14:file_byte=40;
 18:file_byte=w;19:file_byte=w>>8;22:file_byte=h;23:file_byte=h>>8;
 26:file_byte=1;28:file_byte=24;
 default:if(index>=54 && index<length)begin
  p=index-54;py=p/stride;c=p%stride;px=c/3;
  if(c<w*3)case(c%3)0:file_byte=px;1:file_byte=py;2:file_byte=8'h80;endcase
 end
 endcase
end endfunction
initial forever begin
 wait(request);base=address*512;sector_count=sector_count+1;
 // Fixed command/token overhead plus 40 system clocks per received byte.
 repeat(400) @(negedge clk);
 for(b=0;b<512;b=b+1)begin
  repeat(39) @(negedge clk);
  sd_valid=1;sd_byte=file_byte(base+b);@(negedge clk);sd_valid=0;
 end
 sd_end=1;@(negedge clk);sd_end=0;wait(!request);
end
always @(negedge clk)if(output_valid)begin
 x=(count%640)*w/640;y=(count/640)*h/480;
 if(rgb!=={8'h80,y[7:0],x[7:0]})errors=errors+1;
 count=count+1;
end
task image;
input integer width,height;
begin
 w=width;h=height;stride=((w*3+3)/4)*4;length=54+stride*h;
 count=0;sector_count=0;@(negedge clk);begin_cycle=cycles;load=1;
 @(negedge clk);load=0;wait(!ready);wait(ready);repeat(3)@(negedge clk);
 if(count!=307200)errors=errors+1;
 $display("MEDIA %0dx%0d cycles=%0d ms=%0f max_model_fps=%0f sectors=%0d pixels=%0d",
  w,h,cycles-begin_cycle,(cycles-begin_cycle)/100000.0,
  100000000.0/(cycles-begin_cycle),sector_count,count);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 image(160,120);image(320,240);image(640,480);
 if(errors)$fatal(1,"MEDIA BUDGET errors=%0d",errors);
 $display("MEDIA BUDGET: ALL CHECKS PASSED");$finish;
end
initial begin #2000000000;$fatal(1,"timeout");end
endmodule
