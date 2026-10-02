`timescale 1ns/1ps
module tb_audio_wave_pipeline;
reg mclk=0,vclk=0,rst=1,wave_rst=1,enable=0,frame=0;
always #40 mclk=~mclk;
always #20 vclk=~vclk;
wire bclk,lrck,dout,valid;
wire [23:0] left,right;
wire [8:0] y,prev_y;
reg [6:0] index=0;
integer samples=0,errors=0,i,above,below;
hdmi_audio_tone_i2s_64fs tone(.I_mclk(mclk),.I_rst(rst),.I_enable(enable),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(.I_clk(vclk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(valid),
 .O_audio_left_data(left),.O_audio_right_data(right));
audio_wave_snapshot wave(.clk(vclk),.rst(wave_rst),.frame_start(frame),
 .sample_valid(valid),.sample(left),.read_index(index),.read_y(y),.previous_y(prev_y));
always @(posedge vclk) begin #1;if(!rst && valid) samples=samples+1;end
task wait_samples;input integer n;integer before_count;
begin before_count=samples;wait(samples>=before_count+n);@(negedge vclk);end endtask
task capture;
begin wave_rst=1;repeat(3) @(negedge vclk);wave_rst=0;
 wait_samples(140);frame=1;@(negedge vclk);frame=0;repeat(3) @(negedge vclk);end endtask
task inspect;input active;
begin
 above=0;below=0;
 for(i=0;i<128;i=i+1) begin
  index=i;repeat(3) @(negedge vclk);
  if(active) begin if(y<374) above=above+1;if(y>374) below=below+1;end
  else if(y!==374) errors=errors+1;
 end
 if(active && (!above || !below)) errors=errors+1;
 $display("PIPELINE active=%d above=%d below=%d errors=%d",active,above,below,errors);
end endtask
initial begin
 repeat(10) @(negedge vclk);rst=0;capture();inspect(0);
 enable=1;wait_samples(20);capture();inspect(1);
 enable=0;wait_samples(20);capture();inspect(0);
 if(errors) $fatal(1,"WAVE PIPELINE RESULT: %d errors",errors);
 $display("WAVE PIPELINE RESULT: ALL CHECKS PASSED");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
