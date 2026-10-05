`timescale 1ns/1ps
module tb_bmp_reader_scaling;
reg clk=0,rst=1,load=0,sd_valid=0,sd_end=0;
reg [7:0] sd_byte;
wire request,write_request,output_valid,ready;
wire [31:0] address;wire [23:0] rgb;
reg output_ready=1;
integer w=5,h=3,offset=600,stride=16,length=648;
reg scan=0;
integer bpp=24,compression=0,plane_count=1,write_seen=0;
wire scan_done,found;
wire [2:0] found_total;
integer count=0,errors=0,cyc=0,b,i,px,py,exp_x,exp_y,base;
always #5 clk=~clk;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_resume(1'b0),.scan_paused(),.scan_start(scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd10),.scan_target_count(3'd4),
 .scan_done(scan_done),.scan_found_valid(found),.scan_found_sector(),.scan_found_total(found_total),
 .load_start(load),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(write_request),
 .write_req_ack(write_request),.write_ready(output_ready),.sd_sec_read(request),
 .sd_sec_read_addr(address),.sd_sec_read_data(sd_byte),.sd_sec_read_data_valid(sd_valid),
 .sd_sec_read_end(sd_end),.bmp_data_wr_en(output_valid),.bmp_data(rgb));
function [7:0] file_byte;
input integer index;
integer pos,c,x,y;
begin
 file_byte=0;
 case(index)
 0:file_byte=8'h42;1:file_byte=8'h4D;
 2:file_byte=length;3:file_byte=length>>8;4:file_byte=length>>16;5:file_byte=length>>24;
 10:file_byte=offset;11:file_byte=offset>>8;12:file_byte=offset>>16;13:file_byte=offset>>24;
 14:file_byte=40;18:file_byte=w;19:file_byte=w>>8;
 22:file_byte=h;23:file_byte=h>>8;24:file_byte=h>>16;25:file_byte=h>>24;
 26:file_byte=plane_count;28:file_byte=bpp;30:file_byte=compression;
 default: if(index>=offset && index<length) begin
    pos=index-offset;y=pos/stride;c=pos%stride;
    if(c<w*3) begin x=c/3;case(c%3) 0:file_byte=x;1:file_byte=y;2:file_byte=8'h80;endcase end
    else file_byte=8'hEE;
 end
 endcase
end endfunction
// SD source has no byte backpressure, matching the hardware block reader.
initial forever begin
 wait(request);base=address*512;
 for(b=0;b<512;b=b+1) begin
  @(negedge clk);sd_valid=1;sd_byte=file_byte(base+b);
  @(negedge clk);sd_valid=0;
 end
 @(negedge clk);sd_end=1;@(negedge clk);sd_end=0;
 wait(!request);
end
always @(negedge clk) begin
 cyc=cyc+1;output_ready=(cyc%11>3);
 if(write_request) write_seen=write_seen+1;
 if(output_valid) begin
  exp_x=(count%640)*w/640;exp_y=(count/640)*h/480;
  if(rgb!=={8'h80,exp_y[7:0],exp_x[7:0]}) begin
   if(errors<5) $display("FAIL index=%d got=%h expected=%d,%d",count,rgb,exp_x,exp_y);
   errors=errors+1;
  end
  count=count+1;
 end
end
task image;
input integer width,height,pixel_offset;
begin
 w=width;h=height;offset=pixel_offset;stride=((w*3+3)/4)*4;length=offset+stride*h;
 count=0;@(negedge clk);load=1;@(negedge clk);load=0;
 wait(!ready);wait(ready);repeat(5) @(negedge clk);
 if(count!=307200) begin errors=errors+1;$display("FAIL count=%d",count);end
 $display("READER CASE %dx%d offset=%d, output=%d",w,h,offset,count);
end endtask
task reject;
begin
 write_seen=0;count=0;@(negedge clk);load=1;@(negedge clk);load=0;
 wait(!ready);wait(ready);repeat(5) @(negedge clk);
 if(write_seen || count) begin errors=errors+1;$display("FAIL invalid header started write");end
end endtask
initial begin
 repeat(5) @(negedge clk);rst=0;
 scan=1;@(negedge clk);scan=0;wait(scan_done);repeat(5) @(negedge clk);
 if(found_total!=1) begin errors=errors+1;$display("FAIL scanner missed resized BMP");end
 image(5,3,600);image(641,481,54);image(640,1,54);
 bpp=32;reject();bpp=24;compression=1;reject();compression=0;
 w=1281;reject();w=640;h=961;reject();h=-1;reject();h=1;
 plane_count=2;reject();plane_count=1;length=offset+stride*h-1;reject();
 $display("Invalid format, size, top-down and truncated headers rejected");
 if(errors) $fatal(1,"READER RESULT: %d errors",errors);
 $display("READER RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #500000000;$fatal(1,"timeout");end
endmodule
