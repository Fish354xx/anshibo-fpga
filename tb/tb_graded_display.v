`timescale 1ns/1ps
module tb_graded_display;
reg clk=0,rst=1,vs=0,de=0,major=0,loaded=0,overlay=1,selecting=0;
reg[1:0]level=0,candidate=1,target=0,active=0;
reg[9:0]px=0,py=0;always #20 clk=~clk;
wire ready,restore,audio_enable;wire[1:0]audio_level;wire[23:0]rgb;
emergency_audio_frame_gate gate(.clk(clk),.rst(rst),.vs(vs),.de(de),.mode_async(major),.loaded_async(loaded),
 .target_index_async(target),.active_index_async(active),.audio_enable(audio_enable),.picture_ready(ready),.restore_ready(restore));
campus_osd #(.DYNAMIC_TEXT_ENABLE(1),.GRADED_ALERT_ENABLE(1),.SUBTITLE_DEBOUNCE_CYCLES(1)) dut(
 .clk(clk),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h2468AC),.emergency_async(major),
 .subtitle_enable_async(overlay),.settings_async(8'h12),.audio_valid(1'b0),.audio_sample(24'd0),
 .transition_pending_async(1'b0),.dynamic_text_active(1'b0),.dynamic_text_changed(1'b0),.dynamic_text_glyph(10'd0),
 .alert_level_async(level),.alert_candidate_async(candidate),.alert_select_async(selecting),
 .alert_picture_ready(ready),.alert_restore_ready(restore),.alert_audio_level(audio_level),.out_rgb(rgb));
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
task frame;begin de=0;vs=0;cycles(6);vs=1;cycles(6);vs=0;cycles(6);de=1;cycles(3);end endtask
task pixel;input[9:0]x,y;input[23:0]expect_rgb;
begin px=x;py=y;cycles(3);if(rgb!==expect_rgb)$fatal(1,"pixel %0d,%0d=%h expected %h",x,y,rgb,expect_rgb);end endtask
task capture;input integer kind;integer file,x,y;
begin
 if(kind==2)file=$fopen("sim/warning_preview.ppm","w");else file=$fopen("sim/critical_preview.ppm","w");
 $fwrite(file,"P3\n640 480\n255\n");
 for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
  px=x;py=y;cycles(2);$fwrite(file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
 end $fclose(file);end endtask
initial begin force dut.x=px;force dut.y=py;
 cycles(5);rst=0;cycles(12);frame();
 level=1;cycles(8);frame();if(audio_enable||audio_level!=1)$fatal(1,"reminder silence/visible level");
 pixel(8,420,24'hFFC040);pixel(24,100,24'h2468AC);
 major=1;level=2;target=1;active=0;cycles(8);frame();
 if(dut.frame_alert!=1||audio_enable)$fatal(1,"warning published before image ready");
 loaded=1;cycles(8);frame();if(dut.frame_alert!=1||audio_enable)$fatal(1,"wrong cache accepted");
 active=1;cycles(8);frame();
 if(dut.frame_alert!=2||audio_level!=2||!audio_enable)$fatal(1,"warning sound/visual frame alignment");
 overlay=0;cycles(8);frame();pixel(0,0,24'h182838);pixel(8,90,24'hFFC040);
 capture(2);
 level=3;cycles(8);frame();if(audio_level!=3||!audio_enable)$fatal(1,"escalation frame alignment");
 pixel(8,90,24'hBA2028);capture(3);
 selecting=1;candidate=0;cycles(8);frame();pixel(8,380,24'h133C68);
 selecting=0;level=0;major=0;cycles(8);frame();
 if(dut.frame_alert!=3||audio_enable)$fatal(1,"clear should wait for normal cache and silence alarm");
 loaded=0;target=0;cycles(8);frame();if(dut.frame_alert!=3)$fatal(1,"restore wrong bank accepted");
 active=0;cycles(8);frame();if(dut.frame_alert!=0||audio_level!=0)$fatal(1,"normal page not restored");
 pixel(24,100,24'h2468AC);
 $display("GRADED DISPLAY: ALL CHECKS PASSED");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
