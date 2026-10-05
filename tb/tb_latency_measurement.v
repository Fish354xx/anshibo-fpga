`timescale 1ns/1ps
// Quantitative control timing with production 100MHz/20ms and video 25MHz.
// TF/SDRAM/HDMI/speaker are not modeled. No physical latency claim.
module tb_latency_measurement;
reg clk=0,vclk=0,rst=1,vrst=1,key=1,busy=0;
always #5 clk=~clk;
always #20 vclk=~vclk;
wire mode,req;wire[1:0] idx;
emergency_mode_ctrl #(.CLK_FREQ_HZ(100000000),.DEBOUNCE_MS(20)) ctrl(
 .clk(clk),.rst(rst),.key_mode(key),.key_next_press(1'b0),.key_auto_press(1'b0),
 .pause_rotate(1'b0),.scan_done(1'b1),.bmp_ready(1'b1),.first_image_committed(1'b1),
 .display_valid(1'b1),.load_busy(busy),.img_found_count(3'd4),.cur_img_idx(2'd0),
 .emergency_mode(mode),.load_req(req),.load_req_idx(idx),.load_req_is_emergency(),.disp_commit_en());
wire vs,de;
// Use the project's actual line/frame generator, including sync polarity and delay.
video_timing_data #(.DATA_WIDTH(32)) timing(.video_clk(vclk),.rst(vrst),
 .read_req(),.read_req_ack(1'b1),.hs(),.vs(vs),.de(de));
reg gmode=0,loaded=0;reg[1:0] active=0,target=1;
wire audio;
emergency_audio_frame_gate gate(.clk(vclk),.rst(vrst),.vs(vs),.de(de),
 .mode_async(gmode),.loaded_async(loaded),.target_index_async(target),
 .active_index_async(active),.audio_enable(audio));
integer csv,i;realtime tkey,tmode,treq,tcommit,tqualified,taudio;
realtime request_edge=-1,request_accept=-1;
always @(posedge req) if(!rst) request_edge=$realtime;
always @(posedge clk) if(!rst && req) request_accept=$realtime;
realtime phase,extra_delay;
always @(posedge vclk) if(!vrst && de && gate.first_pixel_pending &&
 gate.mode_sync1 && gate.loaded_sync2 && gate.active_sync1==gate.target_sync1)
 tqualified=$realtime;
task control_case;
input integer id;input integer phase_ns;input integer busy_delay_ns;
begin
 rst=1;key=1;busy=(busy_delay_ns!=0);repeat(5)@(negedge clk);rst=0;
 repeat(5)@(negedge clk);#(phase_ns);tkey=$realtime;key=0;
 @(posedge mode);tmode=$realtime;
 if(tmode-tkey<20000000.0 || tmode-tkey>20000100.0)$fatal(1,"unexpected debounce time");
 if(busy_delay_ns!=0) begin
  if(req)$fatal(1,"request while busy");
  #(busy_delay_ns);@(negedge clk);busy=0;
 end
 wait(request_edge>=tkey);wait(request_accept>=tkey);treq=request_edge;
 
 $fdisplay(csv,"control,%0d,%0d,%0d,%0.0f,%0.0f,%0.0f",id,phase_ns,busy_delay_ns,tmode-tkey,treq-tkey,request_accept-tkey);
 $display("MEASURE control %0d: debounce=%0.0f ns request_assert_from_key=%0.0f ns accepted_from_key=%0.0f ns",id,tmode-tkey,treq-tkey,request_accept-tkey);
 repeat(5)@(negedge clk);
end endtask
task gate_case;
input integer id;input integer offset_ns;
begin
 vrst=1;gmode=0;loaded=0;active=0;
 repeat(5)@(negedge vclk);vrst=0;gmode=1;
 // Injection relative to frame start; represents an externally completed image.
 #(offset_ns);@(negedge vclk);tcommit=$realtime;loaded=1;active=1;
 // Audio must not start just because loaded rises, only at eligible frame pixel.
 @(posedge audio);taudio=$realtime;
 if(taudio!=tqualified)$fatal(1,"audio not aligned to qualified frame pixel");
 if(taudio<tcommit || taudio-tcommit>16800400.0)$fatal(1,"frame gate wait outside bound");
 $fdisplay(csv,"gate,%0d,%0d,0,%0.0f,%0.0f,%0.0f",id,offset_ns,tqualified-tcommit,taudio-tqualified,taudio-tcommit);
 $display("MEASURE gate %0d: commit_to_qualified=%0.0f ns qualified_to_enable=%0.0f ns",id,tqualified-tcommit,taudio-tqualified);
 @(negedge vclk);gmode=0;wait(!audio);repeat(5)@(negedge vclk);
end endtask
initial begin
 csv=$fopen("measurements/latency.csv","w");if(!csv)$fatal(1,"CSV open failed");
 $fdisplay(csv,"test,id,phase_or_offset_ns,injected_busy_ns,mode_or_frame_wait_ns,req_assert_or_gate_delay_ns,req_accept_or_total_ns");
 $dumpfile("measurements/latency.vcd");
 $dumpvars(0,key,mode,req,busy,gmode,loaded,active,audio,vs,de);
 control_case(0,1,0);control_case(1,4,0);control_case(2,9,0);
 control_case(3,1,100000);control_case(4,4,100000);control_case(5,9,100000);
 rst=1;
 gate_case(0,0);gate_case(1,1000);gate_case(2,4000000);gate_case(3,8000000);gate_case(4,16000000);
 $fclose(csv);$display("LATENCY: ALL CHECKS PASSED");$finish;
end
initial begin #300000000;$fatal(1,"latency timeout");end
endmodule
