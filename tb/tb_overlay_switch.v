`timescale 1ns/1ps
module tb_overlay_switch;
reg clk=0,rst=1,vs=0,de=0,sw=1;
always #5 clk=~clk;
wire ovs,ode,rvs,rde;wire [23:0] rgb,ref_rgb;
integer errors=0,x,y,visible_diff=0,hidden_diff=0;
campus_osd #(.CLK_FREQ_HZ(1000000),.SUBTITLE_DEBOUNCE_CYCLES(8)) dut(
 .clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h80A0C0),
 .emergency_async(1'b0),.subtitle_enable_async(sw),.settings_async(8'h12),
 .audio_valid(1'b0),.audio_sample(24'd0),.transition_pending_async(1'b0),
 .transition_black_ready(),.out_vs(ovs),.out_de(ode),.out_rgb(rgb));
campus_osd #(.CLK_FREQ_HZ(1000000),.SUBTITLE_DEBOUNCE_CYCLES(8)) reference_osd(
 .clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h80A0C0),
 .emergency_async(1'b0),.subtitle_enable_async(1'b1),.settings_async(8'h12),
 .audio_valid(1'b0),.audio_sample(24'd0),.transition_pending_async(1'b0),
 .transition_black_ready(),.out_vs(rvs),.out_de(rde),.out_rgb(ref_rgb));
task check;input ok; input [255:0] message;begin
 if(ok!==1'b1)begin errors=errors+1;$display("FAIL: %0s",message);end
 else $display("PASS: %0s",message);
end endtask
task cycles;input integer n;begin repeat(n)begin @(posedge clk);#1;end end endtask
task frame;input hidden;begin
 @(negedge clk);vs=1;de=0;cycles(2);@(negedge clk);vs=0;cycles(2);
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin
   @(negedge clk);de=1;cycles(1);
   if(ode!==rde || ovs!==rvs)errors=errors+1;
   if(hidden)begin if(rgb!==24'h80A0C0)hidden_diff=hidden_diff+1;end
   else begin if(rgb!==ref_rgb)visible_diff=visible_diff+1;end
  end
  @(negedge clk);de=0;cycles(2);
 end
end endtask
initial begin
 cycles(3);@(negedge clk);rst=0;cycles(3);
 check(dut.frame_subtitle===1'b1,"reset default visible");
 // Mechanical bounce must not change the debounced state.
 repeat(3)begin @(negedge clk);sw=0;cycles(2);@(negedge clk);sw=1;cycles(4);end
 check(dut.subtitle_stable===1'b1,"reject short switch bounce");
 frame(0);check(visible_diff==0,"enabled full frame equals OSD");
 @(negedge clk);sw=0;cycles(14);
 check(dut.subtitle_stable===1'b0 && dut.frame_subtitle===1'b1,"change waits for frame boundary");
 frame(1);check(hidden_diff==0,"disabled full frame is picture only");
 check(dut.frame_subtitle===1'b0,"disabled committed at frame");
 @(negedge clk);sw=1;cycles(14);
 check(dut.frame_subtitle===1'b0,"re-enable waits for frame");
 frame(0);check(visible_diff==0 && dut.frame_subtitle===1'b1,"text and waveform restored");
 if(errors==0)$display("OVERLAY SWITCH: ALL CHECKS PASSED");else $display("FAIL: errors=%0d",errors);
 $finish;
end
endmodule
