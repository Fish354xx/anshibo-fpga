`timescale 1ns/1ps
module tb_graded_alert_ctrl;
reg clk=0,rst=1,k3=1,k2=1,ready=1,available=1,valid=0,major=0;
always #5 clk=~clk;
reg[3:0]code=0;reg[2:0]value=0;
wire[1:0]local_level,remote_level,effective,candidate;
wire selecting,next_key,major_valid,major_value;
graded_alert_ctrl #(.DEBOUNCE_CYCLES(4),.LONG_CYCLES(40),.SELECT_TIMEOUT(300)) dut(
 .clk(clk),.rst(rst),.key_mode(k3),.key_next(k2),.ready(ready),.major_available(available),
 .command_valid(valid),.command_code(code),.command_value(value),.backend_major(major),
 .local_level(local_level),.remote_level(remote_level),.effective_level(effective),
 .selecting(selecting),.candidate(candidate),.backend_next_key(next_key),
 .major_command_valid(major_valid),.major_command_value(major_value));
always @(posedge clk)if(major_valid)major<=major_value;
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
task short3;begin k3=0;cycles(14);k3=1;cycles(14);end endtask
task next2;begin k2=0;cycles(14);k2=1;cycles(14);end endtask
task send;input[3:0]c;input[2:0]v;begin code=c;value=v;valid=1;cycles(1);valid=0;cycles(10);end endtask
task check;input ok;input[511:0]s;begin if(ok!==1)$fatal(1,"%0s",s);$display("PASS: %0s",s);end endtask
initial begin
 cycles(5);rst=0;cycles(10);
 short3();check(selecting&&candidate==1&&local_level==0,"selection does not publish");
 // Input bounce shorter than debounce does not select a different level.
 k2=0;cycles(1);k2=1;cycles(1);k2=0;cycles(1);k2=1;cycles(8);
 check(candidate==1,"debounce ignores bounce");
 short3();check(local_level==1&&!major&&!selecting,"confirm local reminder preserves normal playback");
 short3();check(candidate==0&&selecting,"active local alert offers clear first");
 next2();next2();check(candidate==2,"cycle to warning");
 short3();check(local_level==2&&major,"confirm warning requests full emergency backend");
 send(13,3);check(remote_level==3&&effective==3,"remote higher level wins");
 send(13,0);check(remote_level==0&&effective==2,"remote clear cannot remove local warning");
 // Long press publishes critical once and release does not open selector.
 k3=0;cycles(75);check(local_level==3&&!selecting,"long press goes directly to critical");
 k3=1;cycles(14);check(!selecting&&local_level==3,"long release suppressed");
 send(13,1);check(effective==3&&remote_level==1,"lower remote alert cannot downgrade local critical");
 short3();short3();check(local_level==0&&effective==1&&!major,"clear local preserves remote reminder");
 send(4,1);check(effective==3&&major,"legacy emergency ON maps to remote critical");
 send(4,0);check(effective==0&&!major,"legacy emergency OFF clears remote only");
 short3();cycles(310);check(!selecting&&local_level==0,"selection timeout cancels without publish");
 ready=0;k3=0;cycles(75);k3=1;cycles(14);check(local_level==0,"not-ready local action ignored");ready=1;
 available=0;short3();next2();short3();check(selecting&&local_level==0,"missing emergency image blocks warning confirmation");
 available=1;short3();check(local_level==2,"warning confirmation after availability restored");
 short3();k2=0;cycles(14);short3();check(next_key==1,"selection key stays masked until release");
 k2=1;cycles(14);check(next_key==1,"released key is high");
 $display("GRADED ALERT CONTROL: ALL CHECKS PASSED");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
