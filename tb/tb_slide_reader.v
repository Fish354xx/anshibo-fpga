`timescale 1ns/1ps
module tb_slide_reader;
reg clk=0,rst=1,request=0;reg[9:0]shift=0;reg incoming=0;
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
 .read_slide_offset(held_shift),.read_slide_in(held_in));
integer count=0,errors=0,expected,source_x,rotation,offset,base,cyc=0;
always @(negedge clk)begin
 cyc=cyc+1;used=(cyc%300<30)?400:0; // Exercise FIFO stalls between bursts.
 if(en)begin
  source_x=(count%640+rotation)%640;
  expected=base+(count/640)*640+source_x;
  if(addr!==expected)begin if(errors<3)$display("FAIL count=%0d addr=%0d expected=%0d",count,addr,expected);errors=errors+1;end
  count=count+1;
 end
end
task image;input integer amount;input direction;input[1:0]index;
begin
 shift=amount;incoming=direction;bank=index;count=0;base=(index==1)?307200:0;
 rotation=(amount==640)?0:(direction&&amount>0)?640-amount:amount;
 repeat(6)@(negedge clk);request=1;wait(ack);@(negedge clk);request=0;
 repeat(5)@(negedge clk);
 // Incoming controls may change mid-frame, but the current raster is immutable.
 shift=123;incoming=~direction;bank=~index;
 wait(finish);@(negedge clk);
 if(count!=307200||held_shift!=amount||held_in!=direction||active!=index)errors=errors+1;
 $display("READER shift=%0d in=%0d bank=%0d checked=%0d",amount,direction,index,count);
 repeat(6)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 image(0,0,0);image(40,0,0);image(320,0,1);image(600,0,1);
 image(640,0,0);image(600,1,1);image(40,1,1);image(0,1,1);
 if(errors)$fatal(1,"SLIDE READER errors=%0d",errors);
 $display("SLIDE READER: ALL CHECKS PASSED");$finish;
end
initial begin #200000000;$fatal(1,"timeout");end
endmodule
