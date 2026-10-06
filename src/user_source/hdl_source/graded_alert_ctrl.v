// 本地与后台预警分别保存，取较高等级。短按选择/确认，长按直接紧急。
// 本模块保存等级；事件编号、区域和正文由事务缓冲模块统一提交。
module graded_alert_ctrl #(
 parameter integer CLK_FREQ_HZ=100000000,
 parameter integer DEBOUNCE_CYCLES=CLK_FREQ_HZ/50,
 parameter integer LONG_CYCLES=CLK_FREQ_HZ*2,
 parameter integer SELECT_TIMEOUT=CLK_FREQ_HZ*10
)(
 input clk,rst,key_mode,key_next,ready,major_available,
 input command_valid,input[3:0]command_code,input[2:0]command_value,
 input backend_major,
 output reg[1:0]local_level,remote_level,
 output[1:0]effective_level,
 output reg selecting,output reg[1:0]candidate,
 output backend_next_key,
 output reg major_command_valid,output reg major_command_value
);
wire mode_stable,next_stable;
alert_key_filter #(.CYCLES(DEBOUNCE_CYCLES)) fm(clk,rst,key_mode,mode_stable);
alert_key_filter #(.CYCLES(DEBOUNCE_CYCLES)) fn(clk,rst,key_next,next_stable);
reg mode_prev,next_prev,long_fired,next_guard;
reg[31:0]held,select_age;
wire mode_release=mode_stable&&!mode_prev;
wire next_press=!next_stable&&next_prev;
wire long_press=!mode_stable&&!long_fired&&held>=LONG_CYCLES-1;
assign effective_level=(local_level>=remote_level)?local_level:remote_level;
assign backend_next_key=(selecting||next_guard)?1'b1:key_next;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  local_level<=0;remote_level<=0;selecting<=0;candidate<=1;
  mode_prev<=1;next_prev<=1;long_fired<=0;next_guard<=0;held<=0;select_age<=0;
  major_command_valid<=0;major_command_value<=0;
 end else begin
  mode_prev<=mode_stable;next_prev<=next_stable;major_command_valid<=0;
  if(mode_stable)begin held<=0;long_fired<=0;end
  else if(!long_fired)begin
   if(long_press)begin
    long_fired<=1;
    if(ready&&major_available)begin local_level<=3;selecting<=0;end
   end else held<=held+1'b1;
  end
  if(selecting)next_guard<=1;
  else if(next_stable)next_guard<=0;
  if(selecting)begin
   if(next_press)begin candidate<=(candidate==3)?0:candidate+1'b1;select_age<=0;end
   else if(select_age>=SELECT_TIMEOUT-1)begin selecting<=0;select_age<=0;end
   else select_age<=select_age+1'b1;
  end else select_age<=0;
  if(mode_release&&!long_fired&&ready)begin
   if(selecting)begin
    if(candidate<2||major_available)begin local_level<=candidate;selecting<=0;end
   end else begin selecting<=1;candidate<=(effective_level!=0)?0:1;select_age<=0;end
  end
  // Long action wins over selection, including timeout/next-key coincidence.
  if(long_press&&ready&&major_available)begin local_level<=3;selecting<=0;end
  if(command_valid)begin
   if(command_code==13 && (command_value<2||major_available))remote_level<=command_value[1:0];
   else if(command_code==4 && (!command_value[0]||major_available))remote_level<=command_value[0]?3:0;
  end
  if(ready && ((effective_level>=2)!=backend_major))begin
   major_command_valid<=1;major_command_value<=effective_level>=2;
  end
 end
end
endmodule

module alert_key_filter #(parameter integer CYCLES=2000000)(
 input clk,rst,key_in,output reg stable
);
reg sync0,sync1;
localparam integer BITS=(CYCLES<2)?1:$clog2(CYCLES);
reg[BITS-1:0]count;
always @(posedge clk or posedge rst)begin
 if(rst)begin sync0<=1;sync1<=1;stable<=1;count<=0;end
 else begin
  sync0<=key_in;sync1<=sync0;
  if(sync1==stable)count<=0;
  else if(count==CYCLES-1)begin stable<=sync1;count<=0;end
  else count<=count+1'b1;
 end
end
endmodule

