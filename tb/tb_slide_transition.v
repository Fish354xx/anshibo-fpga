`timescale 1ns/1ps
module tb_slide_transition;
reg clk=0,rst=1,frame=0,pending=0,bypass=0,read_epoch=0,cancel_request=0;
reg[1:0]mode=1;
wire ready,incoming,mix,epoch,cancel_ack;wire[4:0]level;wire[9:0]shift;
always #5 clk=~clk;
picture_transition #(.SLIDE_ENABLE(1)) dut(.clk(clk),.rst(rst),.frame_start(frame),
 .pending_async(pending),.emergency_async(1'b0),.bypass_async(bypass),.mode_async(mode),
 .read_epoch_async(read_epoch),.cancel_request_async(cancel_request),
 .slide_mix(mix),.slide_epoch(epoch),.cancel_ack(cancel_ack),
 .black_ready(ready),.level(level),.slide_offset(shift),.slide_in(incoming));
integer errors=0,i;reg[9:0]held;
task tick;begin frame=1;@(negedge clk);frame=0;repeat(6)@(negedge clk);end endtask
task check;input good;input[511:0]msg;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",msg);end
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(6)@(negedge clk);
 check(shift==0&&level==16&&!mix,"startup has no animation");
 pending=1;repeat(6)@(negedge clk);
 for(i=1;i<=16;i=i+1)begin
  tick();check(shift==i*40&&level==16&&mix,"joined slide advances without black or fade");
  held=shift;repeat(7)@(negedge clk);check(shift==held,"step held outside frame boundary");
  if(i==5)mode=2;
 end
 check(!ready,"endpoint does not release old bank before memory adopts new-only raster");
 repeat(3)tick();check(shift==640&&level==16&&!ready,"endpoint remains visible while reader delayed");
 read_epoch=epoch;repeat(6)@(negedge clk);check(ready,"memory adoption unlocks commit");
 pending=0;repeat(6)@(negedge clk);tick();
 check(!ready&&shift==0&&!mix&&level==16,"push ends without second animation");
 pending=1;repeat(6)@(negedge clk);tick();check(level==15&&!mix,"FADE setting applies next transaction");
 bypass=1;cancel_request=~cancel_ack;pending=0;repeat(6)@(negedge clk);tick();
 check(level==16&&!mix&&shift==0&&cancel_ack!=cancel_request,"cancel waits for reader fence");
 repeat(3)tick();check(cancel_ack!=cancel_request,"delayed reader cannot free target bank");
 read_epoch=epoch;repeat(6)@(negedge clk);tick();check(cancel_ack==cancel_request,"cancel acknowledges nonmixed raster");
 bypass=0;mode=1;pending=1;repeat(6)@(negedge clk);tick();tick();
 check(mix&&shift==80,"new push starts after cancellation");
 bypass=1;pending=0;cancel_request=~cancel_ack;repeat(6)@(negedge clk);tick();
 check(!mix&&shift==0&&level==16&&!ready,"emergency cancels push directly");
 read_epoch=epoch;repeat(6)@(negedge clk);tick();check(cancel_ack==cancel_request,"push cancellation fenced");
 bypass=0;mode=0;pending=1;repeat(6)@(negedge clk);tick();
 check(ready&&level==16&&!mix,"CUT has no dimming");
 pending=0;repeat(6)@(negedge clk);tick();check(!ready&&level==16,"CUT ends directly");
 if(errors)$fatal(1,"SLIDE CONTROL errors=%0d",errors);
 $display("SLIDE CONTROL: ALL CHECKS PASSED");$finish;
end
endmodule
