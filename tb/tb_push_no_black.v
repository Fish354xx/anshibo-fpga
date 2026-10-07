`timescale 1ns/1ps
module tb_push_no_black;
reg clk=0,rst=1,incoming=0;reg[9:0]shift=0;
wire[23:0]rgb;
always #5 clk=~clk;
campus_osd #(.SLIDE_ENABLE(1),.WAVE_ENABLE(0)) osd(
 .clk(clk),.rst(rst),.in_vs(1'b0),.in_de(1'b1),.in_rgb(24'h80A0C0),
 .emergency_async(1'b0),.subtitle_enable_async(1'b0),.settings_async(8'h12),
 .transition_pending_async(1'b0),.transition_mode_async(2'd1),.transition_bypass_async(1'b0),
 .read_slide_offset_async(shift),.read_slide_in_async(incoming),.audio_valid(1'b0),.audio_sample(24'd0),
 .out_rgb(rgb));
integer errors=0,position=0,i,d,amount;
reg black;
initial begin
 force osd.frame_subtitle=0;force osd.x=position;
 repeat(5)@(negedge clk);rst=0;
 for(d=0;d<2;d=d+1)for(i=0;i<5;i=i+1)begin
  case(i)0:amount=0;1:amount=40;2:amount=320;3:amount=600;4:amount=640;endcase
  shift=amount;incoming=d;repeat(5)@(negedge clk);
  for(position=0;position<640;position=position+1)begin
   repeat(3)@(negedge clk);
   black=0; // Both old and incoming regions must pass their memory pixels.
   if(rgb!==(black?24'd0:24'h80A0C0))begin
    if(errors<3)$display("FAIL mask in=%0d shift=%0d x=%0d rgb=%h",d,amount,position,rgb);
    errors=errors+1;
   end
  end
 end
 if(errors)$fatal(1,"PUSH NO BLACK errors=%0d",errors);
 $display("PUSH NO BLACK: ALL CHECKS PASSED");$finish;
end
endmodule
