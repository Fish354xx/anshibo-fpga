`timescale 1ns/1ps
module tb_startup_system;
reg clk=0,rst=1,mem_done=0;always #5 clk=~clk;
wire req,en,valid;wire [31:0] data;integer count=0;
sd_card_bmp #(.CLK_FREQ_HZ(100000),.SCAN_MAX_SECTOR(400)) dut(
 .clk(clk),.rst(rst),.remote_next(1'b0),.next_block_reason(),.adjustment_switch(1'b0),.contrast_switch(1'b0),.key_next(1'b1),.key_auto(1'b1),.key_mode(1'b1),
 .state_code(),.bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),
 .o_emergency_mode(),.debug_status(),.picture_settings(),.transition_pending(),
 .transition_black_ready(1'b1),.write_finish_toggle(mem_done),.write_buf_idx(),.disp_buf_idx(),
 .write_req(req),.write_req_ack(req),.write_ready(1'b1),.write_en(en),.write_data(data),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
always @(posedge clk)if(en)begin
 count=count+1;if(data!==32'h33221100)$fatal(1,"wrong pixel");
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(dut.load_busy);wait(!dut.bmp_ready);wait(dut.bmp_ready);repeat(10)@(negedge clk);
 if(count!=307200 || valid || !dut.scan_paused || dut.img_found_count!=1)
  $fatal(1,"first image did not wait for SDRAM completion");
 $display("PASS: initial source complete, display waits for memory");
 mem_done=1;wait(valid);
 if(dut.img_found_count!=1)$fatal(1,"first display waits for other images");
 $display("PASS: first image visible before remaining scan");
 wait(dut.scan_done);repeat(5)@(negedge clk);
 if(!valid || dut.img_found_count!=4 || dut.img_idx!=0 || dut.load_busy)
  $fatal(1,"resume lost display or scan state");
 $display("STARTUP SYSTEM: ALL CHECKS PASSED");$finish;
end
initial begin #200000000;$fatal(1,"system timeout");end
endmodule
module sd_card_top(input clk,rst,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid=0,output reg sd_sec_read_end=0,
 output sd_init_done,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 input sd_sec_write,input [31:0] sd_sec_write_addr,output [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
assign sd_init_done=!rst;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
assign sd_sec_write_data=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
integer scenario=0,first_sector=152,b,sector;
function [7:0] media_byte;input integer s,i;begin
 media_byte=0;
 if(s>=first_sector && s<first_sector+4) begin
  case(i)
   0:media_byte="B";1:media_byte="M";2:media_byte=58;10:media_byte=54;
   14:media_byte=40;18:media_byte=1;22:media_byte=1;26:media_byte=1;28:media_byte=24;
   54:media_byte=8'h11;55:media_byte=8'h22;56:media_byte=8'h33;
  endcase
 end else if(s==0 && scenario==0)begin
  case(i)450:media_byte=8'h0C;454:media_byte=32;510:media_byte=8'h55;511:media_byte=8'hAA;endcase
 end else if((s==32 && scenario==0) || (s==0 && scenario!=0))begin
  case(i)
   0:media_byte=8'hEB;11:media_byte=0;12:media_byte=(scenario==2)?4:2;
   13:media_byte=8;14:media_byte=8;16:media_byte=2;
   32:media_byte=8'hE8;33:media_byte=3;36:media_byte=56;44:media_byte=2;
   510:media_byte=8'h55;511:media_byte=8'hAA;
  endcase
 end
end endfunction
initial forever begin
 wait(sd_sec_read);sector=sd_sec_read_addr;
 for(b=0;b<512;b=b+1)begin
  @(negedge clk);sd_sec_read_data_valid=1;sd_sec_read_data=media_byte(sector,b);
  @(negedge clk);sd_sec_read_data_valid=0;
 end
 @(negedge clk);sd_sec_read_end=1;@(negedge clk);sd_sec_read_end=0;wait(!sd_sec_read);
end
endmodule
