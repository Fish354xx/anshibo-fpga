`timescale 1ns/1ps
// Isolate the production SD manager's retirement fence from TF file traffic.
module tb_push_retire;
reg clk=0,rst=1,busy=0,permit=1,mixed=0,ack=0;
reg[1:0]active=0;
wire request;
always #5 clk=~clk;
sd_card_bmp #(.FRAME_READER_FEEDBACK(1)) dut(.clk(clk),.rst(rst),
 .key_next(1'b1),.key_auto(1'b1),.key_mode(1'b1),.adjustment_switch(1'b0),.contrast_switch(1'b0),
 .command_valid(1'b0),.command_code(4'd0),.command_value(3'd0),.remote_next(1'b0),
 .bmp_width(16'd640),.bmp_height(16'd480),.transition_black_ready(1'b0),
 .read_active_index_async(active),.read_slide_mix_async(mixed),
 .transition_cancel_ack_async(ack),.transition_cancel_request(request),
 .write_finish_toggle(1'b0),.write_req_ack(1'b0),.write_ready(1'b1),.SD_MISO(1'b1));
integer errors=0;
task check;input good;input[511:0]msg;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",msg);end
end endtask
initial begin
 force dut.load_busy=busy;force dut.source_done_seen=1;force dut.memory_done_seen=1;
 force dut.disp_commit_en=permit;force dut.display_valid=1;
 force dut.disp_buf_idx=0;force dut.img_idx=0;force dut.o_emergency_mode=0;
 force dut.ctrl_load_req=0;
 repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 busy=1;permit=0;repeat(5)@(negedge clk);
 check(request==1&&!dut.commit_allowed,"abort requires a fresh ack even before mixed feedback arrives");
 mixed=1;repeat(5)@(negedge clk);
 check(!dut.commit_allowed&&!dut.reader_bank_safe,"reader still using both banks cannot retire or load");
 mixed=0;repeat(5)@(negedge clk);
 check(!dut.commit_allowed,"nonmixed flag alone is insufficient without epoch ack");
 ack=request;repeat(5)@(negedge clk);
 check(dut.commit_allowed&&dut.reader_bank_safe,"fresh nonmixed adoption releases cancelled transaction");
 busy=0;repeat(3)@(negedge clk);busy=1;repeat(5)@(negedge clk);
 check(request==0&&!dut.commit_allowed,"next cancellation cannot reuse previous ack");
 ack=request;repeat(5)@(negedge clk);check(dut.commit_allowed,"second cancellation completes");
 permit=1;active=1;repeat(5)@(negedge clk);
 check(!dut.reader_bank_safe,"next write waits for display bank adoption");
 active=0;mixed=1;repeat(5)@(negedge clk);
 check(!dut.reader_bank_safe,"same primary bank still blocked while mixed");
 mixed=0;repeat(5)@(negedge clk);check(dut.reader_bank_safe,"nonmixed current bank safe");
 if(errors)$fatal(1,"PUSH RETIRE errors=%0d",errors);
 $display("PUSH RETIRE: ALL CHECKS PASSED");$finish;
end
endmodule
