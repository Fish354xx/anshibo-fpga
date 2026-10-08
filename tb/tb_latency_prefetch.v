`timescale 1ns/1ps
// Model source and memory completion independently, including delayed writes.
module tb_latency_prefetch;
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
integer csv; realtime t0,trequest,tmode,tcommit;
task measure_emergency;input integer id;begin
 @(negedge clk);trequest=$realtime;code=4;value=1;valid=1;
 @(negedge clk);valid=0;wait(mode);tmode=$realtime;
 wait(index==16&&loaded);tcommit=$realtime;
 $fdisplay(csv,"emergency,%0d,%0.0f,%0.0f,%0.0f",id,tmode-trequest,tcommit-trequest,tcommit-tmode);
 $display("MEASURE emergency case=%0d accepted_ns=%0.0f commit_ns=%0.0f",id,tmode-trequest,tcommit-trequest);
 check(!transition,"emergency bypasses transition");
end endtask
initial begin
 csv=$fopen("measurements/quantitative/prefetch_model.csv","w");
 if(!csv)$fatal(1,"CSV open failed");
 $fdisplay(csv,"test,case,accept_ns,commit_ns,accept_to_commit_ns");
 repeat(5)@(negedge clk);t0=$realtime;rst=0;wait(displayed);
 $fdisplay(csv,"startup_model,0,0,%0.0f,%0.0f",$realtime-t0,$realtime-t0);
 wait(dut.cache_valid);measure_emergency(0);
 command(4,0);wait(index==0&&!mode&&!loaded);
 wait(dut.prefetch_transaction);repeat(100)@(negedge clk);measure_emergency(1);
 $fclose(csv);
 if(errors)$fatal(1,"LATENCY PREFETCH errors=%0d",errors);
 $display("LATENCY PREFETCH: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"latency timeout");end
endmodule
