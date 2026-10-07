`timescale 1ns/1ps
module tb_fat_resources;
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
reg no_config=0,no_alert=0,truncate=0,no_normal=0;
integer page,b,i,chosen,base,count=0,errors=0,identifier,logical,captured=0;
reg[7:0]received[0:511];
initial begin $readmemh("sim/fat_fixture_lbas.hex",lbas);$readmemh("sim/fat_fixture_bytes.hex",disk);end
initial forever begin
 wait(preq);chosen=-1;
 for(i=0;i<128;i=i+1)if(lbas[i]==psector)chosen=i;
 for(b=0;b<512;b=b+1)begin
  repeat(3)@(negedge clk);pvalid=1;pdata=chosen<0?0:disk[chosen*512+b];
  // Fixture volume2048, active FAT6144+32=6176; data start10272.
  if(no_config&&psector==10348&&b>=64&&b<96)pdata=0;
  if(no_normal&&psector==10348&&b<32)pdata=8'hE5;
  if(no_alert&&psector==10276)pdata=0;
  if(truncate&&psector==6177&&b>=88&&b<92)pdata=8'hFF;
  @(negedge clk);pvalid=0;
 end
 pend=1;@(negedge clk);pend=0;wait(!preq);
end
always @(negedge clk)if(vvalid)begin
 if(captured<512)received[captured]=vdata;
 captured=captured+1;
end
task check;input good;input[511:0]message;begin
 if(!good)begin errors=errors+1;$display("FAIL %0s",message);end
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
initial begin
 boot();check(normal_count==3&&active_count==3&&emergency,"directories catalogued independently");
 check(flags==8'h28,"invalid BMP and absent playlist entry reported");
 image(0,4,8);image(1,1,3);image(2,4,1);
 select(16);read(0);check(received[18]==1&&received[56]==9&&!fallback,"emergency path independent");
 truncate=1;select(1);read(0);read(1);read(2);
 check(failed&&flags[6]&&received[0]==0,"truncated fragmented chain returns error and drain data");
 select(1);read(0);check(fallback&&received[18]==1&&!failed,"disabled broken file uses builtin status background");
 truncate=0;no_config=1;boot();check(active_count==3&&!dut.playlist_enabled,"missing optional playlist uses automatic order");
 image(0,1,5);image(1,2,5);image(2,4,5);
 no_alert=1;boot();check(!emergency&&flags[2],"missing emergency resource reported");
 select(16);read(0);check(fallback&&received[18]==1,"missing emergency has builtin fallback");
 no_normal=1;boot();check(normal_count==0&&active_count==0&&flags[1],"missing normal directory has zero resources");
 select(0);read(0);check(fallback&&received[0]=="B","empty daily catalog remains renderable");
 if(errors)$fatal(1,"FAT RESOURCE errors=%0d",errors);
 $display("FAT RESOURCE: ALL CHECKS PASSED");$finish;
end
initial begin #50000000;$fatal(1,"FAT timeout state=%0d",dut.state);end
endmodule
