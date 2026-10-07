`timescale 1ns/1ps
module tb_fat_variants;
reg clk=0,rst=1,init=1,select_file=0,vread=0,pvalid=0,pend=0;
reg[4:0]index=0;reg[31:0]vsector=0;reg[7:0]pdata=0;
wire ready,emergency,failed,fallback,preq,vvalid,vend;
wire[4:0]normal_count,active_count;wire[5:0]seconds;wire[7:0]flags,vdata;wire[31:0]psector;
always #5 clk=~clk;
fat32_resources #(.CLK_FREQ_HZ(1000000)) dut(.clk(clk),.rst(rst),.sd_init_done(init),
 .catalog_ready(ready),.normal_count(normal_count),.active_count(active_count),.emergency_file(emergency),
 .status_flags(flags),.select_file(select_file),.file_index(index),.selected_seconds(seconds),.decoder_failed(1'b0),
 .load_error(failed),.selected_fallback(fallback),.virtual_read(vread),.virtual_sector(vsector),
 .virtual_data(vdata),.virtual_valid(vvalid),.virtual_end(vend),
 .physical_read(preq),.physical_sector(psector),.physical_data(pdata),.physical_valid(pvalid),.physical_end(pend));
reg[31:0]lbas[0:127];reg[7:0]disk[0:65535];
reg no_config=0,no_alert=0,truncate=0,no_normal=0,short_packet=0,timeout_packet=0;
integer page,b,i,chosen,base,count=0,errors=0,identifier,logical,captured=0;
reg[7:0]received[0:511];
initial begin $readmemh("sim/fat_fixture_lbas.hex",lbas);$readmemh("sim/fat_fixture_bytes.hex",disk);end
initial forever begin
 wait(preq);chosen=-1;
 for(i=0;i<128;i=i+1)if(lbas[i]==psector)chosen=i;
 for(b=0;b<(short_packet?16:512);b=b+1)begin
  repeat(3)@(negedge clk);pvalid=1;pdata=chosen<0?0:disk[chosen*512+b];
  // Fixture volume2048, active FAT6144+32=6176; data start10272.
  if(no_config&&psector==10348&&b>=64&&b<96)pdata=0;
  if(no_normal&&psector==10348&&b<32)pdata=8'hE5;
  if(no_alert&&psector==10276)pdata=0;
  if(truncate&&psector==6177&&b>=88&&b<92)pdata=8'hFF;
  @(negedge clk);pvalid=0;
 end
 if(!timeout_packet)pend=1;@(negedge clk);pend=0;wait(!preq);
end
always @(negedge clk)if(vvalid)begin
 if(captured<512)received[captured]=vdata;
 captured=captured+1;
end
task check;input good;input[511:0]message;begin
 if(good!==1'b1)begin errors=errors+1;$display("FAIL %0s",message);end
 else $display("PASS %0s",message);
end endtask
task boot;begin
 rst=1;repeat(5)@(negedge clk);rst=0;wait(ready);repeat(5)@(negedge clk);
end endtask
task select;input[4:0]slot;begin
 index=slot;select_file=1;@(negedge clk);select_file=0;repeat(8)@(negedge clk);
end endtask
task read;input integer sector;begin
 captured=0;vsector=sector;vread=1;wait(vend);@(negedge clk);vread=0;
 repeat(5)@(negedge clk);if(captured!=512)begin errors=errors+1;$display("FAIL sector count=%0d",captured);end
end endtask
task image;input[4:0]slot;input integer id,time_seconds;
integer n,byte_index,position,row,column;
begin
 select(slot);check(seconds==time_seconds,"configured dwell seconds");
 for(n=0;n<5;n=n+1)begin
  read(n);
  for(byte_index=0;byte_index<512;byte_index=byte_index+1)begin
   position=n*512+byte_index;
   if(position>=54&&position<2358)begin
    row=(position-54)/96;column=((position-54)%96)/3;
    case((position-54)%3)
    0:if(received[byte_index]!==column[7:0])errors=errors+1;
    1:if(received[byte_index]!==row[7:0])errors=errors+1;
    2:if(received[byte_index]!==id[7:0])errors=errors+1;
    endcase
   end
  end
 end
 read(0);check(received[0]=="B"&&received[1]=="M"&&!failed,"header rewind maps file start");
end endtask
reg[255:0]variant;integer slot;
initial begin
 if(!$value$plusargs("VARIANT=%s",variant))variant="limits";
 if(variant=="no_card")init=0;
 if(variant=="short")short_packet=1;
 if(variant=="timeout")timeout_packet=1;
 boot();
 if(variant=="limits")begin
  check(normal_count==16&&active_count==16&&flags[4]&&!dut.playlist_enabled,"lowest sixteen numeric assets retained independently of directory order");
  for(slot=0;slot<16;slot=slot+1)begin
   select(slot);read(0);check(received[56]==slot+1&&!fallback,"sorted resource descriptor correct");
  end
 end else if(variant=="bom")begin
  check(active_count==3&&flags==8'h08,"UTF8 BOM and final line without newline accepted");
  image(0,4,8);image(1,1,3);image(2,4,1);
 end else if(variant=="superfloppy")begin
  check(normal_count==3&&active_count==3&&emergency,"FAT32 volume without partition table mounted");
  image(0,4,8);
 end else if(variant=="invalid"||variant=="no_card"||variant=="short"||variant=="timeout")begin
  check(normal_count==0&&active_count==0&&flags[0],"unsupported geometry rejected");
  select(0);read(0);check(fallback&&received[0]=="B","invalid volume still renders builtin status");
 end
 if(errors)$fatal(1,"FAT VARIANTS errors=%0d",errors);
 $display("FAT VARIANTS: ALL CHECKS PASSED %0s",variant);$finish;
end
initial begin #50000000;$fatal(1,"variant timeout state=%0d",dut.state);end
endmodule
