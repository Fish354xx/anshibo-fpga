`timescale 1ns/1ps
module tb_startup_scan;
reg clk=0,rst=1,scan=0,resume_scan=0,load=0,valid=0,ending=0;
reg [7:0] value;wire req,wr,ready,paused,done,found,out_valid;
wire [31:0] addr,found_sector;wire [2:0] total;wire [23:0] rgb;
integer scenario=0,first_sector=152,reads=0,outputs=0,errors=0,b,sector,found_count=0;
always #5 clk=~clk;
bmp_read #(.EARLY_FIRST_IMAGE(1)) dut(.clk(clk),.rst(rst),.ready(ready),
 .scan_start(scan),.scan_resume(resume_scan),.scan_paused(paused),
 .scan_start_sector(32'd0),.scan_max_sector(32'd400),.scan_target_count(3'd4),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_sector),.scan_found_total(total),
 .load_start(load),.load_sector(first_sector),.sd_init_done(1'b1),.state_code(),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(wr),.write_req_ack(wr),.write_ready(1'b1),
 .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(value),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),.bmp_data_wr_en(out_valid),.bmp_data(rgb));
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
 wait(req);sector=addr;reads=reads+1;
 if(scenario==0 && reads<=3)begin
  if((reads==1 && sector!=0)||(reads==2 && sector!=32)||(reads==3 && sector!=152))errors=errors+1;
 end
 for(b=0;b<512;b=b+1)begin
  @(negedge clk);valid=1;value=media_byte(sector,b);
  @(negedge clk);valid=0;
 end
 @(negedge clk);ending=1;@(negedge clk);ending=0;wait(!req);
end
always @(posedge clk)begin
 if(found)begin if(found_sector!=first_sector+found_count)errors=errors+1;found_count=found_count+1;end
 if(out_valid)begin outputs=outputs+1;if(rgb!==24'h332211)errors=errors+1;end
end
task check;input ok;input [399:0] msg;begin
 if(ok!==1'b1)begin errors=errors+1;$display("FAIL: %0s",msg);end else $display("PASS: %0s",msg);
end endtask
task test_case;input integer kind,start;
integer paused_reads;
begin
 scenario=kind;first_sector=start;reads=0;outputs=0;found_count=0;
 @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
 scan=1;@(negedge clk);scan=0;wait(paused);repeat(3)@(negedge clk);
 check(total==1 && !done && ready,"first image pauses scan before other images");
 if(kind==0)check(reads==3,"MBR and FAT32 jump: only 3 header reads");
 if(kind==1)check(reads==2,"superfloppy FAT32 skips metadata");
 if(kind==2)check(reads==3,"invalid BPB falls back to sequential scanning");
 paused_reads=reads;repeat(20)@(negedge clk);check(reads==paused_reads,"scan stays paused until resumed");
 load=1;@(negedge clk);load=0;wait(!ready);wait(ready);repeat(3)@(negedge clk);
 check(outputs==307200 && paused && !done,"first image loaded fully before remaining scan");
 resume_scan=1;@(negedge clk);resume_scan=0;wait(done);repeat(3)@(negedge clk);
 check(found_count==4 && total==4 && !paused,"resume preserves image count and physical order");
end endtask
initial begin
 test_case(0,152);test_case(1,120);test_case(2,2);
 if(errors)$fatal(1,"STARTUP errors=%0d",errors);
 $display("STARTUP SCAN: ALL CHECKS PASSED");$finish;
end
initial begin #500000000;$fatal(1,"startup timeout");end
endmodule
