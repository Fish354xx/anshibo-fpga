`timescale 1ns/1ps
module tb_read_frame_tag;
reg clk=0,rst=1,req=0;reg [1:0] target=0;
wire ack;wire [1:0] active;wire [20:0] addr;
always #5 clk=~clk;
frame_fifo_read dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b1),.O_rd_busy(),
 .App_rd_en(),.App_rd_addr(addr),.read_req(req),.read_req_ack(ack),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_active_index(active),.read_addr_index(target),.read_len(21'd307200),.fifo_aclr(),.wrusedw(10'd0));
initial begin
 repeat(3)@(negedge clk);rst=0;target=1;repeat(5)@(negedge clk);req=1;
 wait(ack);@(negedge clk);req=0;repeat(8)@(negedge clk);
 if(active!==1 || addr!==307200)$fatal(1,"tag differs from selected address");
 target=0;repeat(8)@(negedge clk);
 if(active!==1 || addr!==307200)$fatal(1,"tag changed before next frame request");
 req=1;wait(ack);@(negedge clk);req=0;repeat(8)@(negedge clk);
 if(active!==0 || addr!==0)$fatal(1,"new request did not latch buffer");
 $display("READ FRAME TAG: ALL CHECKS PASSED");$finish;
end
initial begin #100000;$fatal(1,"tag timeout");end
endmodule
