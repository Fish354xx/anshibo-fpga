`timescale 1ns/1ps
module tb_campus_osd;
reg clk=0,rst=1,vs=0,de=0,mode=0;
reg [23:0] rgb=24'h80A0C0;
always #5 clk=~clk;
wire ovs,ode;
wire [23:0] orgb;
campus_osd #(.CLK_FREQ_HZ(1000000),.WAVE_ENABLE(0)) dut(
 .clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(rgb),
 .emergency_async(mode),.subtitle_enable_async(1'b1),.settings_async(8'h12),.transition_pending_async(1'b0),
 .audio_valid(1'b0),.audio_sample(24'd0),
 .transition_black_ready(),.out_vs(ovs),.out_de(ode),.out_rgb(orgb));
integer errors=0,ink=0,shade=0,pixels=0,i,j;
task check;
input condition; input [511:0] message;
begin
 if(!condition) begin errors=errors+1; $display("FAIL: %0s",message); end
 else $display("PASS: %0s",message);
end
endtask
task frame;
input active_mode;
begin
 mode=active_mode; de=0; repeat(4) @(negedge clk);
 vs=1; repeat(4) @(negedge clk); vs=0; repeat(4) @(negedge clk);
 ink=0; shade=0; pixels=0;
 for(j=0;j<480;j=j+1) begin
   for(i=0;i<640;i=i+1) begin
     de=1; @(posedge clk); #1;
     if(!ode || ovs) errors=errors+1;
     if(j>=8 && j<36 || j>=40 && j<68 || j>=440 && j<472) begin
       if(orgb==(active_mode?24'hFFD060:24'hFFFFFF)) ink=ink+1;
       else if(orgb==24'h202830) shade=shade+1;
       else errors=errors+1;
     end else if(orgb!==rgb) errors=errors+1;
     pixels=pixels+1;
     @(negedge clk);
   end
   de=0; repeat(8) @(negedge clk);
 end
 check(pixels==307200,"all 640x480 active pixels preserve timing");
 check(ink>300 && shade>1000,"Chinese text and translucent bands rendered");
 check(dut.frame_mode==active_mode,"mode label latched at frame boundary");
end
endtask
initial begin
 repeat(5) @(negedge clk); rst=0;
 frame(0); frame(1); frame(0);
 check(dut.scroll==1,"scroll advances once per two frames");
 check({dut.h10,dut.h1,dut.m10,dut.m1,dut.s10,dut.s1}==24'd0,"uptime does not run faster than its clock parameter");
 repeat(70000) @(negedge clk);
 check(dut.s1==1,"uptime advances one second at configured frequency");
 check(errors==0,"background and one-cycle video alignment preserved");
 if(errors) $fatal(1,"OSD errors=%0d",errors);
 $display("OSD RESULT: ALL CHECKS PASSED"); $finish;
end
initial begin #20000000; $fatal(1,"OSD timeout"); end
endmodule
