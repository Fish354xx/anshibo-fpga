`timescale 1ns/1ps
// Model source and memory completion independently, including delayed writes.
module tb_prefetch_scheduler;
reg clk=0,rst=1,valid=0,next=0,parser_ready=1,failed=0,finish=0,mixed=0;
reg[3:0]code=0;reg[4:0]value=0;reg[1:0]active_bank=0;reg cancel_ack=0;
reg transition_ready=0;
wire displayed,mode,loaded,transition,cancel_request;wire[4:0]index;
wire[1:0]display_bank;wire[5:0]seconds;wire[2:0]block_reason;
always #5 clk=~clk;
sd_card_bmp #(.RESOURCE_ENABLE(1),.PREFETCH_ENABLE(1),.REMOTE_ENABLE(1),
 .FRAME_READER_FEEDBACK(1),.CLK_FREQ_HZ(1000)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.key_mode(1'b1),
 .adjustment_switch(1'b0),.contrast_switch(1'b0),.command_valid(valid),.command_code(code),
 .command_value(value),.remote_next(next),.display_valid(displayed),.resource_index(index),
 .resource_seconds(seconds),.o_emergency_mode(mode),.o_emergency_loaded(loaded),
 .transition_pending(transition),.transition_black_ready(transition_ready),
 .transition_cancel_request(cancel_request),.transition_cancel_ack_async(cancel_ack),
 .read_active_index_async(active_bank),.read_slide_mix_async(mixed),.disp_buf_idx(display_bank),
 .next_block_reason(block_reason),.write_finish_toggle(finish),.write_req_ack(1'b0),
 .write_ready(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),.SD_MISO(1'b1));
integer age=0,latency=0,starts=0,errors=0,cycles=0,baseline;
reg running=0,forbid_two=0;
initial begin
 force dut.sd_init_done=1;force dut.resource_catalog_ready=1;
 force dut.resource_normal_count=3;force dut.resource_active_count=3;
 force dut.bmp_ready=parser_ready;force dut.bmp_load_failed=failed;
 force dut.resource_load_error=0;force dut.resource_hold_seconds=1;
 force dut.resource_selected_fallback=0;force dut.bmp_data_wr_en=0;force dut.write_req=0;
end
always @(negedge clk)begin
 cycles=cycles+1;
 if(!mixed&&cycles%4==0)active_bank=display_bank;
 cancel_ack=cancel_request;
 if(dut.load_start_pulse)begin
  starts=starts+1;age=0;running=1;parser_ready=0;
  latency=(dut.load_idx==1)?1200:(dut.load_idx==2)?800:30;
 end else if(running)begin
  age=age+1;
  if(age==latency)parser_ready=1;
  if(age==latency+20)begin finish=~finish;running=0;end
 end
 if(forbid_two&&index==2)begin errors=errors+1;$display("FAIL ordinary prefetch leaked during emergency");end
end
task check;input good;input[511:0]message;begin
 if(good!==1'b1)begin errors=errors+1;$display("FAIL %0s",message);end
 else $display("PASS %0s",message);
end endtask
task command;input[3:0]op;input[4:0]arg;begin
 @(negedge clk);code=op;value=arg;valid=1;@(negedge clk);valid=0;repeat(4)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;wait(displayed);wait(dut.prefetch_transaction);
 command(3,1);repeat(1010)@(negedge clk);
 check(index==0&&!transition&&!dut.cache_valid,"preload never switches before request and completion");
 check(dut.u_emergency_mode_ctrl.auto_due,"deadline remains pending while large preload unfinished");
 wait(parser_ready);repeat(3)@(negedge clk);
 check(!dut.cache_valid&&!dut.using_cache,"source completion alone cannot make cache usable");
 wait(dut.using_cache);repeat(3)@(negedge clk);
 check(starts==2&&dut.load_idx==1&&transition,"deadline reuses complete cache without another TF read");
 command(3,0);mixed=1;active_bank=1;transition_ready=1;
 wait(index==1);baseline=starts;repeat(20)@(negedge clk);
 check(starts==baseline,"old bank cannot be written while reader remains mixed");
 mixed=0;wait(dut.prefetch_transaction&&dut.load_idx==2);forbid_two=1;
 command(4,1);check(mode&&index==1,"emergency request accepted during background load");
 wait(index==16);check(loaded&&!transition,"completed ordinary preload discarded before emergency");
 forbid_two=0;command(4,0);wait(index==1&&!mode&&!loaded);
 wait(dut.cache_valid);check(dut.cache_index==2,"next cache rebuilt after emergency restore");
 baseline=starts;command(2,0);wait(index==0);
 check(starts==baseline+1,"arbitrary SHOW cache miss reads requested file");
 wait(dut.prefetch_transaction);check(block_reason==0,"NEXT accepted while preloading");
 @(negedge clk);next=1;@(negedge clk);next=0;wait(dut.using_cache);
 check(index==0,"early manual NEXT waits for complete target cache");
 wait(index==1);check(seconds==1,"cached picture keeps its metadata");
 if(errors)$fatal(1,"PREFETCH SCHEDULER errors=%0d",errors);
 $display("PREFETCH SCHEDULER: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"scheduler timeout index=%0d",index);end
endmodule
