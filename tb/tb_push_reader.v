`timescale 1ns/1ps
module tb_push_reader;
reg clk=0,rst=1,request=0;reg[9:0]shift=0;reg incoming=0;reg[1:0]target=1;reg epoch=0;wire held_mix,held_epoch;
reg[1:0]bank=0;reg[9:0]used=0;
wire ack,finish,en,clear;wire[20:0]addr;wire[1:0]active;
wire[9:0]held_shift;wire held_in;
always #5 clk=~clk;
frame_fifo_read #(.SLIDE_ENABLE(1),.BURST_SIZE(256)) dut(.rst(rst),.mem_clk(clk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),
 .App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(en),.App_rd_addr(addr),
 .read_req(request),.read_req_ack(ack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_active_index(active),.read_addr_index(bank),.read_len(21'd307200),
 .fifo_aclr(clear),.wrusedw(used),.slide_offset(shift),.slide_in(incoming),
 .slide_target_index(target),.slide_mix(1'b1),.slide_epoch(epoch),.read_slide_mix(held_mix),.read_slide_epoch(held_epoch),.read_slide_offset(held_shift),.read_slide_in(held_in));
integer count=0,errors=0,expected,source_x,rotation,offset,base,cyc=0,n,k;reg saved_epoch;integer target_base;
always @(negedge clk)begin
 cyc=cyc+1;used=(cyc%300<30)?400:0; // Exercise FIFO stalls between bursts.
 if(en)begin
  source_x=(count%640+rotation)%640;
  expected=((count%640+rotation>=640)?target_base:base)+(count/640)*640+source_x;
  if(addr!==expected)begin if(errors<3)$display("FAIL count=%0d addr=%0d expected=%0d",count,addr,expected);errors=errors+1;end
  count=count+1;
 end
end
task image;input integer amount;input direction;input[1:0]index;
begin
 shift=amount;incoming=direction;bank=index;count=0;base=(index==1)?307200:0;
 rotation=amount;target=(index==0)?1:0;target_base=(target==1)?307200:0;epoch=~epoch;saved_epoch=epoch;
 repeat(6)@(negedge clk);request=1;wait(ack);@(negedge clk);request=0;
 repeat(5)@(negedge clk);
 // Incoming controls may change mid-frame, but the current raster is immutable.
 shift=123;incoming=~direction;bank=~index;target=index;epoch=~epoch;
 wait(finish);@(negedge clk);
 if(count!=307200||held_shift!=amount||held_in!=direction||active!=((amount==640)?((index==0)?1:0):index)||!held_mix||held_epoch!=saved_epoch)errors=errors+1;
 $display("READER shift=%0d in=%0d bank=%0d checked=%0d",amount,direction,index,count);
 repeat(6)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<2;k=k+1)for(n=0;n<=16;n=n+1)image(n*40,0,k);
 if(errors)$fatal(1,"PUSH READER errors=%0d",errors);
 $display("PUSH READER: ALL CHECKS PASSED");$finish;
end
initial begin #300000000;$fatal(1,"timeout");end
endmodule
