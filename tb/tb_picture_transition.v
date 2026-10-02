`timescale 1ns/1ps
module tb_picture_transition;
reg clk=0,rst=1,vs=0,de=0,pending=0,emergency=0;
reg busy=0,source_done=0,memory_done=0,valid=1,permit=1;
wire ready,commit,request;
wire [4:0] level;
wire [23:0] rgb;
always #5 clk=~clk;
picture_transition ctrl(.clk(clk),.rst(rst),.frame_start(vs),.pending_async(pending),
 .emergency_async(emergency),.black_ready(ready),.level(level));
frame_commit_gate gate(.load_busy(busy),.source_done(source_done),.memory_done(memory_done),
 .display_valid(valid),.emergency_mode(emergency),.display_permit(permit),.black_ready(ready),
 .transition_pending(request),.commit_allowed(commit));
campus_osd osd(.clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h80A0C0),
 .emergency_async(emergency),.settings_async(8'h12),.transition_pending_async(pending),
 .transition_black_ready(),.out_vs(),.out_de(),.out_rgb(rgb));
integer errors=0,i,c,l;
reg [4:0] saved;
task check;
input condition;input [511:0] message;
begin if(!condition) begin errors=errors+1;$display("FAIL: %0s",message);end
else $display("PASS: %0s",message);end
endtask
task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
task frame;
begin vs=1;cycles(1);vs=0;cycles(6);end
endtask
initial begin
 cycles(5);rst=0;cycles(6);
 check(level==16 && !ready,"startup full opacity without transition");
 busy=1;source_done=1;#1;
 check(!request && !commit,"source completion alone cannot switch buffers");
 memory_done=1;#1;
 check(request && !commit,"completed normal image waits for black handshake");
 pending=request;cycles(5);
 for(i=15;i>=0;i=i-1) begin
  frame();if(level!==i) errors=errors+1;
  saved=level;cycles(10);if(level!==saved) errors=errors+1;
 end
 check(level==0 && ready && commit,"16 frame fade-out reaches black before commit");
 repeat(4) frame();check(level==0 && ready,"black holds until producer acknowledges commit");
 busy=0;pending=0;cycles(5);
 frame();frame();frame();
 check(level==0 && !ready,"two frame settling interval hides buffer adoption");
 for(i=1;i<=16;i=i+1) begin frame();if(level!==i) errors=errors+1;end
 check(level==16,"16 frame fade-in restores exact full opacity");
 pending=1;cycles(5);frame();frame();
 emergency=1;cycles(5);frame();
 check(level==16 && !ready,"emergency cancels transition at next frame boundary");
 busy=1;#1;check(commit && !request,"emergency commit bypasses transition wait");
 emergency=0;permit=0;#1;check(commit && !request,"rejected stale transaction retires without waiting");
 permit=1;valid=0;#1;check(commit && !request,"first image bypasses transition wait");
 rst=1;cycles(3);rst=0;pending=0;cycles(5);frame();
 // Check every channel value and all 17 levels, including exact endpoint identity.
 for(l=0;l<=16;l=l+1) for(c=0;c<256;c=c+1)
  if(osd.fade_channel(c,l)!==((c*l)>>4)) errors=errors+1;
 check(errors==0,"4352 opacity cases and previous state checks passed");
 // Cancel a request before black; recovery must not deadlock.
 pending=1;cycles(5);frame();frame();pending=0;cycles(5);frame();
 repeat(18) frame();check(level==16 && !ready,"cancelled transaction recovers without black handshake");
 // Background y=0 has no overlay. The actual OSD pixel must fade with the controller.
 pending=1;cycles(5);frame();
 de=1;@(posedge clk);#1;
 check(rgb==24'h7896B4,"integrated RGB path applies level 15/16");
 @(negedge clk);de=0;
 if(errors) $fatal(1,"TRANSITION RESULT: %0d errors",errors);
 $display("TRANSITION RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
