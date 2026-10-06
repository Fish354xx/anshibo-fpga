`timescale 1ns/1ps
module tb_graded_audio;
reg clk=0,rst=1,enable=1;reg[1:0]level=1;always #5 clk=~clk;
wire b,l,d;
hdmi_audio_tone_i2s_64fs #(.GRADED_ENABLE(1),.WARNING_PERIOD_FRAMES(40),.WARNING_ON_FRAMES(8),.NOTE_HOLD_FRAMES(10)) dut(
 .I_mclk(clk),.I_rst(rst),.I_enable(enable),.I_alert_level(level),.O_i2s_BCLK(b),.O_i2s_LRCK(l),.O_i2s_DOUT(d));
integer n,on_samples=0,off_samples=0;
task frame;begin @(negedge l);#1;end endtask
initial begin #100;rst=0;repeat(12)frame();
 if(dut.S_sample_word!=0)$fatal(1,"reminder not silent");
 level=2;repeat(5)frame();
 for(n=0;n<100;n=n+1)begin frame();
  if(dut.S_sample_word==0)off_samples=off_samples+1;else on_samples=on_samples+1;
 end
 if(on_samples==0||off_samples==0)$fatal(1,"warning not intermittent");
 level=3;repeat(6)frame();
 for(n=0;n<40;n=n+1)begin frame();if(dut.S_sample_word==0)$fatal(1,"critical has unintended silent gap");end
 enable=0;repeat(8)frame();if(dut.S_sample_word!=0)$fatal(1,"gate off not silent");
 $display("GRADED AUDIO: ALL CHECKS PASSED on=%0d off=%0d",on_samples,off_samples);$finish;
end
initial begin #5000000;$fatal(1,"timeout");end
endmodule
