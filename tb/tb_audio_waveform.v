`timescale 1ns/1ps
module tb_audio_waveform;
reg clk=0,rst=1,vs=0,de=0,valid=0;
reg [23:0] sample=0;
reg [6:0] index=0;
wire [8:0] ry,py;
wire [23:0] rgb;wire ode,ovs;
integer errors=0,i,x,y,trace_count=0,grid_count=0;
integer target,previous_target;
reg [23:0] expected;
always #5 clk=~clk;
audio_wave_snapshot snap(.clk(clk),.rst(rst),.frame_start(vs),.sample_valid(valid),
 .sample(sample),.read_index(index),.read_y(ry),.previous_y(py));
campus_osd osd(.clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h80A0C0),
 .emergency_async(1'b0),.subtitle_enable_async(1'b1),.settings_async(8'h12),.transition_pending_async(1'b0),
 .transition_black_ready(),.audio_valid(valid),.audio_sample(sample),
 .out_vs(ovs),.out_de(ode),.out_rgb(rgb));
task check;input condition;input [511:0] message;
begin if(!condition) begin errors=errors+1;$display("FAIL: %0s",message);end
else $display("PASS: %0s",message);end endtask
task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
task push;input [23:0] value;
begin sample=value;valid=1;cycles(1);valid=0;cycles(1);end endtask
task frame_start;begin de=0;vs=1;cycles(1);vs=0;cycles(4);end endtask
initial begin
 cycles(5);rst=0;cycles(5);check(ry==374,"reset shows a flat line before any snapshot");
 for(i=0;i<64;i=i+1) push(24'h200000);
 frame_start();check(!snap.have_snapshot && ry==374,"partial audio block is not published");
 for(i=0;i<64;i=i+1) push(24'hE00000);
 check(snap.block_ready && !snap.have_snapshot,"complete audio block waits for frame boundary");
 frame_start();index=0;cycles(3);check(ry==342,"positive sample maps above center");
 index=64;cycles(3);check(ry==406 && py==342,"negative sample and adjacent point form vertical edge");
 // Render the complete published block without altering any DUT registers.
 frame_start();
 for(y=0;y<480;y=y+1) begin
  for(x=0;x<640;x=x+1) begin
   de=1;@(posedge clk);#1;
   if(ode!==1'b1 || ovs!==1'b0) errors=errors+1;
   if(x>=64 && x<576 && y>=332 && y<418) begin
    target=((x-64)/4<64)?342:406;
    previous_target=((x-64)/4<=64)?342:406;
    expected=24'h202830;
    if(y==374 || y==350 || y==398 || x==192 || x==320 || x==448) expected=24'h304850;
    if(x==64 || x==575 || y==332 || y==417) expected=24'h80A0B0;
    if(((x-64)%4==0 && y>=previous_target && y<=target) ||
       ((x-64)%4!=0 && y+1>=target && y<=target+1)) expected=24'h00FFD0;
    if(rgb!==expected) begin if(errors<3) $display("FAIL pixel %d,%d got=%h exp=%h",x,y,rgb,expected);errors=errors+1;end
    if(rgb==24'h00FFD0) trace_count=trace_count+1;
    if(rgb==24'h304850) grid_count=grid_count+1;
   end
   @(negedge clk);
  end
  de=0;cycles(8);
 end
 check(trace_count>1000 && grid_count>1000,"waveform, vertical joins and grid rendered with aligned pixels");
 check(errors==0,"all waveform panel pixels match independent model");
 for(i=0;i<128;i=i+1) push(24'd0);
 cycles(3);check(ry==406,"next capture cannot change the visible waveform mid-frame");
 frame_start();index=64;cycles(3);check(ry==374,"silent audio replaces waveform with center line");
 for(i=0;i<128;i=i+1) push(i[0]?24'h7FFFFF:24'h800000);
 frame_start();index=0;cycles(3);check(ry==408,"negative full-scale clips within panel");
 index=1;cycles(3);check(ry==340 && py==408,"positive full-scale clips within panel");
 rst=1;cycles(2);rst=0;cycles(3);check(ry==374,"reset discards old waveform snapshots");
 if(errors) $fatal(1,"WAVE RESULT: %d errors",errors);
 $display("WAVE RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
