`timescale 1ns/1ps
// Measure production video 25MHz frame gate; no button/control latency included.
// TF/SDRAM/HDMI/speaker are not modeled. No physical latency claim.
module tb_latency_frame_measure;
reg vclk=0,vrst=1;
always #20 vclk=~vclk;
wire vs,de;
// Use the project's actual line/frame generator, including sync polarity and delay.
video_timing_data #(.DATA_WIDTH(32)) timing(.video_clk(vclk),.rst(vrst),
 .read_req(),.read_req_ack(1'b1),.hs(),.vs(vs),.de(de));
reg gmode=0,loaded=0;reg[1:0] active=0,target=1;
wire audio;
emergency_audio_frame_gate gate(.clk(vclk),.rst(vrst),.vs(vs),.de(de),
 .mode_async(gmode),.loaded_async(loaded),.target_index_async(target),
 .active_index_async(active),.audio_enable(audio));
integer csv;realtime tcommit,tqualified,taudio;
always @(posedge vclk) if(!vrst && de && gate.first_pixel_pending &&
 gate.mode_sync1 && gate.loaded_sync2 && gate.active_sync1==gate.target_sync1)
 tqualified=$realtime;
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
 csv=$fopen("measurements/quantitative/frame_gate.csv","w");if(!csv)$fatal(1,"CSV open failed");
 $fdisplay(csv,"test,id,phase_or_offset_ns,injected_busy_ns,mode_or_frame_wait_ns,req_assert_or_gate_delay_ns,req_accept_or_total_ns");
 $dumpfile("sim/latency_frame.vcd");
 $dumpvars(0,gmode,loaded,active,audio,vs,de);
 gate_case(0,0);gate_case(1,1000);gate_case(2,4000000);gate_case(3,8000000);gate_case(4,16000000);
 $fclose(csv);$display("LATENCY: ALL CHECKS PASSED");$finish;
end
initial begin #300000000;$fatal(1,"latency timeout");end
endmodule
