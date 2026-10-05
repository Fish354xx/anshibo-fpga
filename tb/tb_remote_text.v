`timescale 1ns/1ps
module tb_remote_text;
reg clk=0,vc=0,rst=1,rx=1,vs=0,emergency=0;
always #5 clk=~clk;
always #20 vc=~vc;
wire tx,valid,ready,opened,active,changed,frame;
wire[3:0]code;wire[9:0]glyph,read_glyph;wire[6:0]length;wire[5:0]index;
uart_console dut(.clk(clk),.rst(rst),.rx(rx),.tx(tx),.next_block_reason(3'd0),
 .debug_status(16'h400C),.state_code(4'd1),.picture_settings(8'h12),
 .auto_status(1'b0),.overlay_status(1'b1),.text_ready(ready),.text_open(opened),.text_length(length),
 .command_valid(valid),.command_code(code),.text_glyph(glyph));
remote_text_buffer buffer(.write_clk(clk),.write_rst(rst),.command_valid(valid),.command_code(code),
 .glyph(glyph),.ready(ready),.transaction_open(opened),.length(length),
 .video_clk(vc),.video_rst(rst),.frame_start(frame),.read_index(index),
 .active(active),.changed(changed),.read_glyph(read_glyph));
campus_osd #(.DYNAMIC_TEXT_ENABLE(1),.WAVE_ENABLE(0),.SUBTITLE_DEBOUNCE_CYCLES(1)) osd(
 .clk(vc),.rst(rst),.in_vs(vs),.in_de(1'b1),.emergency_async(emergency),
 .subtitle_enable_async(1'b1),.in_rgb(24'h000000),.settings_async(8'h12),
 .audio_valid(1'b0),.audio_sample(24'd0),.transition_pending_async(1'b0),
 .dynamic_text_active(active),.dynamic_text_changed(changed),.dynamic_text_glyph(read_glyph),
 .dynamic_text_index(index),.dynamic_frame_start(frame));
integer replies=0,k,i,row,col;
reg[511:0]response=0,last_response=0;
reg[7:0]received;
initial forever begin
 @(negedge tx);#13020;
 for(k=0;k<8;k=k+1)begin received[k]=tx;#8680;end
 if(tx!==1)$fatal(1,"stop bit");
 response={response[503:0],received};
 if(received==10)begin last_response=response;response=0;replies=replies+1;end
end
task byte_send;input[7:0]c;integer n;
begin rx=0;#8680;for(n=0;n<8;n=n+1)begin rx=c[n];#8680;end rx=1;#8780;end endtask
task command;input[511:0]s;input integer size;input[511:0]expected;integer n,target;
begin target=replies+1;for(n=size-1;n>=0;n=n-1)byte_send(s[n*8+:8]);byte_send(10);
 wait(replies==target);if(last_response!==expected)$fatal(1,"%0s => %0s",s,last_response);
 $display("PASS text command: %0s",s);end endtask
task new_frame;begin @(negedge vc);vs=1;repeat(5)@(negedge vc);vs=0;repeat(5)@(negedge vc);end endtask
initial begin
 #100;rst=0;#1000;
 command("TCOMMIT",7,{"ERR TEXT",8'd13,8'd10});
 command("TBEGIN",6,{"OK TBEGIN",8'd13,8'd10});
 command("TCHAR 021",9,{"OK TCHAR",8'd13,8'd10}); // A
 command("TCHAR 05F",9,{"OK TCHAR",8'd13,8'd10}); // 今
 command("TCHAR 256",9,{"ERR RANGE",8'd13,8'd10}); // first unsupported ID
 command("TCHAR 0G0",9,{"ERR RANGE",8'd13,8'd10});
 if(active||length!=2)$fatal(1,"partial text exposed or invalid append accepted");
 command("TCOMMIT",7,{"OK TCOMMIT",8'd13,8'd10});
 if(ready||active)$fatal(1,"commit must wait for video boundary");
 command("TBEGIN",6,{"ERR BUSY",8'd13,8'd10});
 new_frame();if(!active||!ready)$fatal(1,"frame commit or acknowledgement failed");
 force osd.x=0;force osd.y=452;#120;
 if(read_glyph!=33)$fatal(1,"first character mismatch");
 force osd.x=16;#120;if(read_glyph!=95)$fatal(1,"Chinese character mismatch");
 force osd.x=32;#120;if(read_glyph!=0)$fatal(1,"tail must be blank");
 force osd.x=0;
 command("TBEGIN",6,{"OK TBEGIN",8'd13,8'd10});
 command("TCHAR 042",9,{"OK TCHAR",8'd13,8'd10}); // lowercase b
 #120;if(read_glyph!=33)$fatal(1,"writing inactive bank changed live caption");
 command("TCOMMIT",7,{"OK TCOMMIT",8'd13,8'd10});
 new_frame();#120;if(read_glyph!=66)$fatal(1,"replacement did not switch bank");
 // Pixel alignment: every bit of a lowercase glyph matches generated ROM.
 for(row=0;row<16;row=row+1)begin
  force osd.y=448+row;
  for(col=0;col<16;col=col+1)begin
   force osd.x=col;#120;
   if(osd.ink!==osd.dynamic_font_rom[66*16+row][15-col])$fatal(1,"glyph pixel alignment");
  end
 end
 release osd.x;release osd.y;
 emergency=1;new_frame();#120;if(osd.use_dynamic)$fatal(1,"custom text overrides emergency");
 emergency=0;new_frame();
 command("TDEFAULT",8,{"OK TDEFAULT",8'd13,8'd10});new_frame();
 if(active)$fatal(1,"default restore failed");
 command("TBEGIN",6,{"OK TBEGIN",8'd13,8'd10});
 command("TCOMMIT",7,{"ERR RANGE",8'd13,8'd10});
 for(i=0;i<64;i=i+1)command("TCHAR 021",9,{"OK TCHAR",8'd13,8'd10});
 command("TCHAR 021",9,{"ERR RANGE",8'd13,8'd10});
 if(length!=64)$fatal(1,"length limit failed");
 command("TCOMMIT",7,{"OK TCOMMIT",8'd13,8'd10});new_frame();
 rst=1;#100;rst=0;#500;if(active||opened||length!=0)$fatal(1,"reset defaults failed");
 $display("REMOTE TEXT: ALL CHECKS PASSED");$finish;
end
initial begin #250000000;$fatal(1,"timeout");end
endmodule
