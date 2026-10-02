`timescale 1ns/1ps
module tb_picture_settings;
reg clk=0,rst=1,next_key=1,auto_key=1,emergency=0;
reg vs=0,de=0;
wire [23:0] adjusted_pixel;
always #5 clk=~clk;
wire next_press,auto_press,active;
wire [7:0] settings;
picture_key_control #(.CLK_FREQ_HZ(10000),.DEBOUNCE_MS(1),.LONG_PRESS_MS(10)) keys(
 .clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.emergency_mode(emergency),
 .next_press(next_press),.auto_press(auto_press),.settings_active(active),.settings(settings));
campus_osd osd(.clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h80A0C0),
 .emergency_async(emergency),.settings_async(settings),.transition_pending_async(1'b0),
 .transition_black_ready(),.out_vs(),.out_de(),.out_rgb(adjusted_pixel));
integer errors=0,next_count=0,auto_count=0,i,b,c,p,delta,gain,expected;
always @(posedge clk) begin
 if(next_press) next_count=next_count+1;
 if(auto_press) auto_count=auto_count+1;
end
task check;
input condition;input [511:0] message;
begin
 if(!condition) begin errors=errors+1;$display("FAIL: %0s",message);end
 else $display("PASS: %0s",message);
end
endtask
task cycles;
input integer n;begin repeat(n) @(negedge clk);end
endtask
task press;
input which;input integer duration;
begin
 if(which) auto_key=0;else next_key=0;
 cycles(duration);
 if(which) auto_key=1;else next_key=1;
 cycles(30);
end
endtask
task start_frame;
begin
 de=0;vs=0;cycles(5);vs=1;cycles(3);vs=0;cycles(3);de=1;
 @(posedge clk);#1;@(negedge clk);
end
endtask
initial begin
 cycles(5);rst=0;cycles(20);
 check(settings==8'h12,"default levels 2/4 with adjustment off");
 press(0,30);press(1,30);
 check(next_count==1 && auto_count==1,"normal short releases retain next/auto actions");
 press(1,160);
 check(active && auto_count==1,"long KEY4 enters without toggling auto-play");
 press(0,30);
 check(settings[5:3]==3,"short KEY2 increases brightness");
 press(1,30);
 check(settings[5:3]==2,"short KEY4 decreases brightness");
 press(0,160);
 check(settings[6] && next_count==1,"long KEY2 selects contrast without next image");
 for(i=0;i<6;i=i+1) press(0,30);
 check(settings[2:0]==4,"contrast upper limit saturates");
 for(i=0;i<6;i=i+1) press(1,30);
 check(settings[2:0]==0,"contrast lower limit saturates");
 press(0,160);
 for(i=0;i<6;i=i+1) press(0,30);
 check(settings[5:3]==4,"brightness upper limit saturates");
 for(i=0;i<6;i=i+1) press(1,30);
 check(settings[5:3]==0,"brightness lower limit saturates");
 emergency=1;cycles(5);press(0,30);press(1,160);
 check(!active && next_count==1 && auto_count==1,"emergency cancels adjustment and ignores keys");
 emergency=0;cycles(5);press(1,160);press(1,160);
 check(!active && auto_count==1,"long entry/exit emits no short action");
 // Exhaustive 8-bit channel validation, all 25 brightness/contrast combinations.
 for(b=0;b<5;b=b+1) for(c=0;c<5;c=c+1) for(p=0;p<256;p=p+1) begin
   delta=p-128;
   case(c)
   0: gain=delta>>>1;
   1: gain=(delta*3)>>>2;
   2: gain=delta;
   3: gain=(delta*5)>>>2;
   4: gain=(delta*3)>>>1;
   endcase
   expected=gain+128+(b-2)*32;
   if(expected<0) expected=0;
   if(expected>255) expected=255;
   if(osd.correct_channel(p[7:0],b[2:0],c[2:0])!==expected[7:0]) errors=errors+1;
 end
 check(errors==0,"6400 pixel cases: levels and clipping correct");
 start_frame;
 check(adjusted_pixel==24'h405060,"configured brightness and contrast affect background pixels");
 press(1,160);press(0,30);
 check(settings[5:3]==1 && adjusted_pixel==24'h405060,"mid-frame parameter change waits for next frame");
 start_frame;
 check(adjusted_pixel==24'h607080,"new parameter applied consistently at frame boundary");
 emergency=1;start_frame;
 check(adjusted_pixel==24'h80A0C0,"emergency frame bypasses user brightness and contrast");
 if(errors) $fatal(1,"Settings errors=%0d",errors);
 $display("SETTINGS RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"Settings timeout");end
endmodule
