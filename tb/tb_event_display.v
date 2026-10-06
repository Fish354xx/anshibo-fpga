`timescale 1ns/1ps
module tb_event_display;
reg clk=0,vc=0,rst=1,cmd_valid=0,vs=0,de=0,major_ready=0,restore_ready=1,legacy=0;
always #5 clk=~clk;always #20 vc=~vc;
reg[2:0]cmd=0;reg[15:0]id=0,crc=0;
reg[1:0]level=0,local_level=0,remote_level=0;
reg[4:0]area=0;reg[6:0]body=0;reg[9:0]glyph=0;
reg[9:0]px=0,py=0;
wire[1:0]effective=(local_level>=remote_level)?local_level:remote_level;
wire result_valid,apply_valid,active_valid,busy,pending,bank,install,read_bank,shown;
wire[3:0]result;wire[1:0]apply_level,active_level,pending_level,shown_level,audio_level;
wire[15:0]active_id,active_crc,pending_id,shown_id;
wire[15:0]pending_generation,shown_generation;
wire[4:0]pending_area;wire[6:0]pending_body,read_index;
wire[9:0]data;wire[2:0]event_state;wire[23:0]rgb;
event_packet_buffer packet(.clk(clk),.rst(rst),.cmd_valid(cmd_valid),.cmd(cmd),.event_id(id),.check_crc(crc),
 .level(level),.area_length(area),.body_length(body),.glyph(glyph),.ready(1'b1),.major_available(1'b1),
 .legacy_change(legacy),.local_level(local_level),.result_valid(result_valid),.result(result),
 .apply_valid(apply_valid),.apply_level(apply_level),.active_valid(active_valid),.active_id(active_id),
 .active_crc(active_crc),.active_level(active_level),.busy(busy),.event_state(event_state),
 .video_clk(vc),.video_rst(rst),.install(install),.shown_remote(shown),.shown_id(shown_id),.shown_level(shown_level),
 .shown_generation(shown_generation),.pending_generation(pending_generation),
 .video_pending(pending),.pending_bank(bank),.pending_id(pending_id),.pending_level(pending_level),
 .pending_area_length(pending_area),.pending_body_length(pending_body),.read_bank(read_bank),.read_index(read_index),.read_glyph(data));
always @(posedge clk)if(apply_valid)remote_level<=apply_level;
campus_osd #(.DYNAMIC_TEXT_ENABLE(1),.GRADED_ALERT_ENABLE(1),.EVENT_ENABLE(1),.SUBTITLE_DEBOUNCE_CYCLES(1)) display(
 .clk(vc),.rst(rst),.in_vs(vs),.in_de(de),.in_rgb(24'h2468AC),.emergency_async(effective>=2),
 .subtitle_enable_async(1'b1),.settings_async(8'h12),.audio_valid(1'b0),.audio_sample(24'd0),
 .transition_pending_async(1'b0),.dynamic_text_active(1'b0),.dynamic_text_changed(1'b0),.dynamic_text_glyph(10'd0),
 .alert_level_async(effective),.alert_candidate_async(2'd0),.alert_select_async(1'b0),
 .alert_picture_ready(major_ready),.alert_restore_ready(restore_ready),.alert_audio_level(audio_level),
 .event_valid_async(active_valid),.event_remote_wins_async(remote_level>local_level),
 .event_pending(pending),.event_pending_bank(bank),.event_pending_id(pending_id),.event_pending_level(pending_level),
 .event_pending_generation(pending_generation),.event_shown_generation(shown_generation),
 .event_pending_area(pending_area),.event_pending_body(pending_body),.event_data(data),
 .event_install(install),.event_read_bank(read_bank),.event_read_index(read_index),
 .event_shown_remote(shown),.event_shown_id(shown_id),.event_shown_level(shown_level),.out_rgb(rgb));
task cycles;input integer n;begin repeat(n)@(negedge vc);end endtask
task frame;begin de=0;vs=0;cycles(8);vs=1;cycles(8);vs=0;cycles(8);de=1;cycles(6);end endtask
task send;input[2:0]c;input[3:0]r;
begin @(negedge clk);cmd=c;cmd_valid=1;@(negedge clk);cmd_valid=0;
 wait(result_valid);#1;if(result!==r)$fatal(1,"event result %0d expected %0d",result,r);repeat(2)@(negedge clk);end endtask
task append;input[9:0]g;begin glyph=g;send(2,1);end endtask
task words1;begin append(33);append(34);append(35);append(36);append(37);end endtask
task words2;begin append(40);append(41);append(42);append(43);append(44);end endtask
task check;input condition;input[511:0]message;
begin if(condition!==1)$fatal(1,"%0s",message);$display("PASS: %0s",message);end endtask
integer row,col,file,x,y;
initial begin force display.x=px;force display.y=py;
 #100;rst=0;cycles(12);frame();
 id=1;level=1;area=2;body=3;send(1,0);words1();crc=16'h84BC;send(3,2);cycles(8);frame();
 check(display.frame_alert==1&&shown_id==1&&shown&&event_state==2,"first event displayed and acknowledged");
 // Check every actual pixel of the first area glyph.
 for(row=0;row<16;row=row+1)for(col=0;col<16;col=col+1)begin
  px=64+col;py=396+row;cycles(3);
  if(rgb!== (display.dynamic_font_rom[33*16+row][15-col]?24'hFFFFFF:24'h182838))$fatal(1,"area glyph pixel mismatch");
 end
 id=2;level=3;send(1,0);words2();
 check(active_id==1&&display.frame_alert==1,"upload keeps old event");
 crc=16'h1F4F;send(3,9);check(active_id==1,"invalid CRC keeps old event");
 crc=16'h1F4E;send(3,2);cycles(8);frame();
 check(display.frame_alert==1&&shown_id==1&&busy,"new severity cannot use old event text while loading");
 major_ready=1;cycles(8);frame();
 check(display.frame_alert==3&&shown_id==2&&event_state==2&&!busy,"new level/area/body install on one frame");
 px=64;py=164;cycles(3);check(data==40&&display.event_glyph==40,"new area selected");
 px=0;py=448;cycles(3);check(data==42&&display.event_glyph==42,"new body selected");
 file=$fopen("sim/event_preview.ppm","w");$fwrite(file,"P3\n640 480\n255\n");
 for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin px=x;py=y;cycles(2);$fwrite(file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);end
 $fclose(file);
 local_level=3;cycles(8);frame();check(!shown&&event_state==3,"local tie wins and reports blocked");
 id=3;level=1;area=1;body=1;send(1,0);append(56);append(57);crc=16'h4CE9;send(3,2);cycles(8);frame();
 check(!busy&&event_state==3&&display.frame_alert==3,"hidden lower event installed without leaking text");
 local_level=0;restore_ready=0;cycles(8);frame();check(display.frame_alert==3&&!shown,"restoration holds complete old local page");
 restore_ready=1;cycles(8);frame();check(shown&&shown_id==3&&shown_level==1&&event_state==2,"cached remote event shown after local clear");
 px=112;py=420;cycles(3);check(display.event_glyph==57,"reminder body from its own event");
 id=2;send(5,10);check(active_id==3,"wrong clear ID rejected");id=3;send(5,5);
 // Reuse after clear must not inherit the previous event's display acknowledgement.
 level=1;area=1;body=1;send(1,0);append(33);append(34);crc=16'h3241;send(3,2);cycles(8);
 de=0;vs=0;cycles(8);vs=1;cycles(8);vs=0;cycles(8);
 check(!busy&&event_state==1,"same ID new generation stays pending before first pixel");
 de=1;cycles(6);check(event_state==2,"new generation acknowledged only at its first pixel");
 id=3;send(5,5);cycles(8);frame();
 check(event_state==0&&!shown&&display.frame_alert==0,"targeted clear returns daily page");
 $display("EVENT DISPLAY: ALL CHECKS PASSED");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
