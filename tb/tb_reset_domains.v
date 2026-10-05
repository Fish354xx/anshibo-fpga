`timescale 1ns/1ps
module tb_reset_domains;
reg a=0,b=0,request=1;
always #5 a=~a;
always #12 b=~b;
wire ra,rb;
reset_domain_sync ua(a,request,ra),ub(b,request,rb);
integer ca=0,cb=0;
always @(posedge a) if(!request)begin
 ca=ca+1;#0.001;
 if(ra !== (ca<2))$fatal(1,"SD reset release not two local edges");
end
always @(posedge b)if(!request)begin
 cb=cb+1;#0.001;
 if(rb !== (cb<2))$fatal(1,"MEM reset release not two local edges");
end
initial begin
 #1;request=0;#80;request=1;ca=0;cb=0;#0.001;
 if(!ra||!rb)$fatal(1,"asynchronous assertion failed");
 #6;request=0;#80;
 $display("RESET DOMAINS: ALL CHECKS PASSED");$finish;
end
endmodule
