`timescale 1ns/1ps
module tb_slide_transition;
reg clk=0,rst=1,frame=0,pending=0,bypass=0;
reg[1:0]mode=1;
wire ready,incoming;wire[4:0]level;wire[9:0]shift;
wire commit,request;
frame_commit_gate gate(.load_busy(1'b1),.source_done(1'b1),.memory_done(1'b1),
 .display_valid(1'b1),.emergency_mode(bypass),.display_permit(1'b1),
 .black_ready(ready),.commit_allowed(commit),.transition_pending(request));
always #5 clk=~clk;
picture_transition #(.SLIDE_ENABLE(1)) dut(.clk(clk),.rst(rst),.frame_start(frame),
 .pending_async(pending),.emergency_async(1'b0),.bypass_async(bypass),.mode_async(mode),
 .black_ready(ready),.level(level),.slide_offset(shift),.slide_in(incoming));
integer errors=0,i;reg[9:0]held;
task tick;begin frame=1;@(negedge clk);frame=0;repeat(6)@(negedge clk);end endtask
task check;input good;input[511:0]msg;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",msg);end
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(6)@(negedge clk);
 check(shift==0&&level==16,"startup has no animation");
 pending=1;repeat(6)@(negedge clk);
 for(i=1;i<=16;i=i+1)begin
  tick();check(shift==i*40,"slide-out advances 40 pixels/frame");
  held=shift;repeat(7)@(negedge clk);check(shift==held,"step held outside frame boundary");
  if(i==5)mode=2; // New setting must not alter the current transaction.
 end
 check(ready&&level==0,"commit occurs only at fully hidden endpoint");
 repeat(3)tick();check(shift==640&&ready,"endpoint holds until commit");
 pending=0;repeat(6)@(negedge clk);tick();tick();tick();
 for(i=15;i>=0;i=i-1)begin tick();check(shift==i*40&&level==16,"slide-in endpoint/order");end
 check(!ready&&shift==0,"completed slide returns to idle");
 pending=1;repeat(6)@(negedge clk);tick();check(level==15&&shift==0,"new FADE setting applies next time");
 bypass=1;repeat(6)@(negedge clk);tick();check(level==16&&shift==0&&!ready,"emergency entry cancels animation");
 check(commit&&!request,"completed emergency picture commits directly");
 pending=0;repeat(6)@(negedge clk);repeat(3)tick();
 check(level==16&&shift==0,"restoration bypass stays immediate");
 check(commit&&!request,"completed restoration bypasses transition");
 bypass=0;mode=0;pending=1;repeat(6)@(negedge clk);tick();
 check(ready&&level==16&&shift==0,"CUT handshake has no visual dimming");
 pending=0;repeat(6)@(negedge clk);tick();check(!ready&&level==16,"CUT ends without fade-in");
 if(errors)$fatal(1,"SLIDE CONTROL errors=%0d",errors);
 $display("SLIDE CONTROL: ALL CHECKS PASSED");$finish;
end
endmodule
