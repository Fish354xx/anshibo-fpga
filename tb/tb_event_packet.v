`timescale 1ns/1ps
module tb_event_packet;
reg clk=0,vc=0,rst=1,valid=0,install=0,ready=1,available=1,legacy=0,shown=0;
always #5 clk=~clk;always #20 vc=~vc;
reg[2:0]cmd=0;reg[15:0]id=0,check_crc=0,shown_id=0;
reg[1:0]level=0,local_level=0,shown_level=0;
reg[4:0]area=0;reg[6:0]body=0,read_index=0;
reg[9:0]glyph=0;reg read_bank=0;
wire result_valid,apply_valid,active_valid,busy,pending,pending_bank;
wire[3:0]result;wire[1:0]apply_level,active_level;
wire[15:0]active_id,active_crc,generation;wire[2:0]event_state;wire[9:0]data;
integer applies=0;
event_packet_buffer dut(.clk(clk),.rst(rst),.cmd_valid(valid),.cmd(cmd),.event_id(id),.check_crc(check_crc),
 .level(level),.area_length(area),.body_length(body),.glyph(glyph),.ready(ready),.major_available(available),
 .legacy_change(legacy),.local_level(local_level),.result_valid(result_valid),.result(result),
 .apply_valid(apply_valid),.apply_level(apply_level),.active_valid(active_valid),.active_id(active_id),
 .active_crc(active_crc),.active_generation(generation),.active_level(active_level),.busy(busy),.event_state(event_state),
 .video_clk(vc),.video_rst(rst),.install(install),.shown_remote(shown),.shown_id(shown_id),.shown_level(shown_level),.shown_generation(generation),
 .video_pending(pending),.pending_bank(pending_bank),.read_bank(read_bank),.read_index(read_index),.read_glyph(data));
always @(posedge clk)if(apply_valid)applies=applies+1;
always @(posedge vc)if(install&&pending)read_bank<=pending_bank;
task send;input[2:0]c;input[3:0]expected;
begin @(negedge clk);cmd=c;valid=1;@(negedge clk);valid=0;
 wait(result_valid);#1;if(result!==expected)$fatal(1,"cmd %0d result %0d expected %0d",c,result,expected);
 $display("PASS event command %0d result %0d",c,result);repeat(2)@(negedge clk);end endtask
task append;input[9:0]g;begin glyph=g;send(2,1);end endtask
task display_install;
begin wait(pending);@(negedge vc);install=1;@(negedge vc);install=0;wait(!busy);repeat(4)@(negedge clk);end endtask
task same_payload;begin append(33);append(34);append(35);append(36);append(37);end endtask
reg[15:0]reference_crc;integer n,before_apply;
initial begin
 #100;rst=0;repeat(6)@(negedge clk);
 reference_crc=16'hFFFF;for(n=0;n<9;n=n+1)reference_crc=dut.crc_byte(reference_crc,8'd49+n);
 if(reference_crc!=16'h29B1)$fatal(1,"CRC known vector");
 id=1;level=1;area=2;body=3;send(1,0);same_payload();
 if(active_valid)$fatal(1,"partial upload became active");
 if(dut.crc!=16'h84BC)$fatal(1,"canonical header/glyph CRC");
 check_crc=16'h84BD;send(3,9);if(active_valid)$fatal(1,"bad CRC committed");
 check_crc=16'h84BC;send(3,2);if(!busy||active_id!=1||apply_level!=1)$fatal(1,"commit not accepted atomically");
 send(1,6);display_install();
 read_index=0;#10;if(data!=33)$fatal(1,"area first word");read_index=16;#10;if(data!=35)$fatal(1,"body first word");
 shown=1;shown_id=1;shown_level=1;repeat(6)@(negedge clk);if(event_state!=2)$fatal(1,"display status not applied");
 before_apply=applies;send(1,0);same_payload();send(3,3);if(applies!=before_apply||busy)$fatal(1,"duplicate re-applied");
 send(1,0);append(33);check_crc=16'h84BC;send(3,8);if(active_id!=1)$fatal(1,"incomplete upload overwrote active");send(4,4);
 send(1,0);same_payload();check_crc=16'h84BD;send(3,9);if(active_id!=1||active_crc!=16'h84BC)$fatal(1,"CRC failure overwrote old event");send(4,4);
 id=2;send(1,0);same_payload();check_crc=0;send(3,9);send(4,4);
 available=0;level=2;send(1,14);available=1;ready=0;send(1,12);ready=1;
 area=0;send(1,11);area=2;
 id=1;level=2;send(1,0);same_payload();check_crc=dut.crc;send(3,10);if(active_level!=1)$fatal(1,"same-ID change accepted");send(4,4);
 id=2;level=2;send(1,0);glyph=607;send(2,11);same_payload();append_overflow();
 check_crc=dut.crc;send(3,2);if(active_id!=2||active_level!=2)$fatal(1,"new event metadata mismatch");
 // Accepted clear cancels pending event without altering the in-flight bank bundle.
 id=1;send(5,10);id=2;send(5,5);if(active_valid||apply_level!=0)$fatal(1,"targeted clear failed");
 display_install();if(event_state!=0)$fatal(1,"clear state");send(5,13);
 id=3;level=1;send(1,0);same_payload();check_crc=dut.crc;send(3,2);display_install();
 legacy=1;@(negedge clk);legacy=0;repeat(3)@(negedge clk);if(active_valid)$fatal(1,"legacy template did not invalidate packet");
 // Full capacity including high-byte glyph codes and the final physical RAM word.
 id=10;level=2;area=16;body=64;send(1,0);
 for(n=0;n<80;n=n+1)append(n<16?606:n);
 check_crc=16'h91C5;send(3,2);display_install();read_index=79;#10;
 if(data!=79||active_id!=10)$fatal(1,"maximum payload boundary");
 // Independent Python fixture: distinct valid strings with the same CRC16.
 id=51;level=1;area=1;body=2;send(1,0);append(33);append(1);append(529);check_crc=16'hF5EF;send(3,2);display_install();
 before_apply=applies;send(1,0);append(33);append(16);append(1);send(3,10);
 if(applies!=before_apply||active_crc!=16'hF5EF)$fatal(1,"CRC collision misclassified as duplicate");
 $display("EVENT PACKET: ALL CHECKS PASSED");$finish;
end
task append_overflow;begin glyph=99;send(2,8);end endtask
initial begin #1000000;$fatal(1,"timeout");end
endmodule

