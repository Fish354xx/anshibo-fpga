`timescale 1ns/1ps
module tb_emergency_frame_audio;
reg clk=0,rst=1,vs=0,de=0,mode=0,loaded=0;
reg [1:0] target=1,active=0;wire audio;
integer errors=0,i;
always #5 clk=~clk;
emergency_audio_frame_gate dut(.clk(clk),.rst(rst),.vs(vs),.de(de),
 .mode_async(mode),.loaded_async(loaded),.target_index_async(target),
 .active_index_async(active),.audio_enable(audio));
task cycles;input integer n;begin repeat(n)begin @(posedge clk);#1;end end endtask
task check;input ok;input [399:0] msg;begin
 if(ok!==1'b1)begin errors=errors+1;$display("FAIL: %0s",msg);end else $display("PASS: %0s",msg);
end endtask
task blank_frame;begin
 @(negedge clk);de=0;vs=1;cycles(2);@(negedge clk);vs=0;cycles(6);
end endtask
task first_pixel;begin @(negedge clk);de=1;cycles(1);end endtask
initial begin
 cycles(3);@(negedge clk);rst=0;cycles(6);
 check(!audio,"reset silent");
 @(negedge clk);mode=1;cycles(6);
 repeat(10)begin blank_frame;first_pixel;check(!audio,"no audio while emergency image loading");end
 @(negedge clk);loaded=1;cycles(6);blank_frame;first_pixel;
 check(!audio,"committed image waits for actual read buffer");
 @(negedge clk);active=1;cycles(6);
 check(!audio,"matching buffer mid-frame does not start audio");
 blank_frame;check(!audio,"vertical blank stays silent");first_pixel;
 check(audio,"first emergency pixel enables audio");
 cycles(20);check(audio,"audio stays enabled throughout frame");
 @(negedge clk);mode=0;cycles(4);check(!audio,"exit stops audio without waiting for reload");
 @(negedge clk);loaded=0;mode=1;cycles(6);blank_frame;first_pixel;
 check(!audio,"new entry rejects stale buffer when not committed");
 @(negedge clk);rst=1;cycles(1);check(!audio,"reset clears pending audio");
 if(errors)$fatal(1,"AUDIO FRAME errors=%0d",errors);
 $display("AUDIO FRAME: ALL CHECKS PASSED");$finish;
end
endmodule
