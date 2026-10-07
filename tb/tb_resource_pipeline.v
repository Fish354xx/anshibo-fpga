`timescale 1ns/1ps
module tb_resource_pipeline;
reg clk=0,rst=1,valid=0,truncate=0,bad_emergency=0,pvalid=0,pend=0,finish_toggle=0,cancel_ack=0;
reg[3:0]code=0;reg[4:0]value=0;
reg[7:0]pdata=0;reg[1:0]active_bank=0;
wire display,mode,loaded,write_req,write_en,busy,transition,cancel_request,fallback;
wire[31:0]write_data;wire[1:0]display_bank;
wire[4:0]normal_count,playlist_count,index;
wire[7:0]flags;wire[5:0]seconds;
always #5 clk=~clk;
sd_card_bmp #(.RESOURCE_ENABLE(1),.REMOTE_ENABLE(1),.FRAME_READER_FEEDBACK(1),.CLK_FREQ_HZ(1000000)) dut(
 .clk(clk),.rst(rst),.adjustment_switch(1'b0),.contrast_switch(1'b0),
 .command_valid(valid),.command_code(code),.command_value(value),.remote_next(1'b0),
 .key_next(1'b1),.key_auto(1'b1),.key_mode(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),
 .display_valid(display),.o_emergency_mode(mode),.o_emergency_loaded(loaded),
 .resource_normal_count(normal_count),.resource_active_count(playlist_count),.resource_index(index),
 .resource_seconds(seconds),.resource_flags(flags),.display_fallback(fallback),
 .transition_pending(transition),.transition_black_ready(1'b1),.read_active_index_async(active_bank),
 .read_slide_mix_async(1'b0),.transition_cancel_request(cancel_request),.transition_cancel_ack_async(cancel_ack),
 .write_finish_toggle(finish_toggle),.disp_buf_idx(display_bank),.write_req(write_req),.write_req_ack(write_req),
 .write_ready(1'b1),.write_en(write_en),.write_data(write_data),.SD_MISO(1'b1));
reg[31:0]lbas[0:127];reg[7:0]disk[0:65535];
integer b,i,chosen,pixel=0,errors=0,frames=0,tick=0,expected_id,ex,ey;
assign busy=dut.load_busy;
initial begin
 $readmemh("sim/fat_fixture_lbas.hex",lbas);$readmemh("sim/fat_fixture_bytes.hex",disk);
 force dut.sd_init_done=1;
 force dut.physical_sec_data=pdata;force dut.physical_sec_valid=pvalid;force dut.physical_sec_end=pend;
end
initial forever begin
 wait(dut.physical_sec_read);chosen=-1;
 for(i=0;i<128;i=i+1)if(lbas[i]==dut.physical_sec_addr)chosen=i;
 for(b=0;b<512;b=b+1)begin
  repeat(3)@(negedge clk);pvalid=1;pdata=chosen<0?0:disk[chosen*512+b];
  if(truncate&&dut.physical_sec_addr==6177&&b>=88&&b<92)pdata=8'hFF;
  if(bad_emergency&&dut.physical_sec_addr==11268&&b==28)pdata=32;
  @(negedge clk);pvalid=0;
 end
 pend=1;@(negedge clk);pend=0;wait(!dut.physical_sec_read);
end
always @(negedge clk)begin
 tick=tick+1;
 if(tick%500==0)begin active_bank=display_bank;cancel_ack=cancel_request;end
 if(write_req)pixel=0;
 if(write_en)begin
  ex=(pixel%640)*32/640;ey=(pixel/640)*24/480;
  expected_id=dut.load_idx==16?9:dut.load_idx==1?1:4;
  if(!dut.resource_load_error&&!dut.resource_selected_fallback)begin
   if(dut.load_idx==16)begin if(write_data!==32'h09000000)errors=errors+1;end
   else if(write_data!=={expected_id[7:0],ey[7:0],ex[7:0],8'd0})errors=errors+1;
  end
  if(dut.resource_selected_fallback&&write_data!==32'h18283800)errors=errors+1;
  pixel=pixel+1;
  if(pixel==307200)begin finish_toggle=~finish_toggle;frames=frames+1;end
 end
end
task command;input[3:0]op;input[4:0]arg;begin
 code=op;value=arg;valid=1;@(negedge clk);valid=0;wait(busy);wait(!busy);repeat(600)@(negedge clk);
end endtask
task check;input good;input[511:0]msg;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",msg);end
 else $display("PASS %0s",msg);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;wait(display);repeat(600)@(negedge clk);
 check(index==0&&normal_count==3&&playlist_count==3&&seconds==8,"fragmented first image commits with playlist metadata");
 command(2,1);check(index==1&&seconds==3,"second configured image commits");
 command(2,2);check(index==2&&seconds==1,"repeated playlist resource commits");
 command(4,1);check(mode&&loaded&&index==16,"independent emergency resource commits");
 command(4,0);check(!mode&&!loaded&&index==2,"emergency restores configured slot");
 truncate=1;command(2,1);check(index==2&&flags[6]&&!busy,"broken chain does not replace displayed image or deadlock writer");
 command(2,1);check(index==1&&fallback,"disabled resource commits explicit fallback");
 bad_emergency=1;code=4;value=1;valid=1;@(negedge clk);valid=0;
 wait(mode&&loaded&&index==16&&fallback);repeat(600)@(negedge clk);
 check(flags[7]&&!busy,"bad emergency header automatically commits builtin emergency fallback");
 command(4,0);check(!mode&&index==1,"fallback emergency still restores previous daily slot");
 if(errors)$fatal(1,"RESOURCE PIPELINE errors=%0d",errors);
 $display("RESOURCE PIPELINE: ALL CHECKS PASSED frames=%0d",frames);$finish;
end
initial begin #1500000000;$fatal(1,"pipeline timeout state=%0d busy=%0d",dut.filesystem.resources.state,busy);end
endmodule
