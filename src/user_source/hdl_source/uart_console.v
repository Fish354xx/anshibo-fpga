// 文件：uart_console.v
// 职责：串口命令解析、状态快照及电脑控制；8N1，大小写不敏感。
// 帧缓存、图像和音频处理仍在FPGA内部；串口仅传输人工命令。
module uart_console #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer BAUD=115200,
    parameter integer EXTENDED_STATUS=0,
    parameter integer GRADED_ALERT_ENABLE=0,
    parameter integer EVENT_ENABLE=0
)(
    input clk,rst,rx,output tx,
    input [2:0] next_block_reason,
    input [15:0] debug_status,
    input [3:0] state_code,
    input [7:0] picture_settings,
    input auto_status,overlay_status,text_ready,text_open,
    input [6:0] text_length,
    input [1:0] effective_alert,local_alert,remote_alert,
    input event_busy,event_result_valid,input[3:0]event_result,
    input event_active_valid,input[15:0]event_active_id,event_active_crc,
    input[1:0]event_active_level,input[2:0]event_state,
    input[4:0]event_active_area,input[6:0]event_active_body,
    output reg event_cmd_valid,output reg[2:0]event_cmd,
    output reg[15:0]event_id,event_crc,
    output reg[1:0]event_level,output reg[4:0]event_area,
    output reg[6:0]event_body,output reg[9:0]event_glyph,
    output reg next_pulse,command_valid,
    output reg [3:0] command_code,
    output reg [2:0] command_value,
    output reg [9:0] text_glyph,
    output reg overlay_override,overlay_value,adjust_override,adjust_value,
    output reg select_override,select_value,soft_reset
);
wire [7:0] rx_data;wire rx_valid,rx_error,tx_ready;
reg [7:0] tx_data;reg tx_start;
uart_rx_8n1 #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD(BAUD)) receiver(
 .clk(clk),.rst(rst),.rx(rx),.data(rx_data),.valid(rx_valid),.framing_error(rx_error));
uart_tx_8n1 #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD(BAUD)) sender(
 .clk(clk),.rst(rst),.data(tx_data),.start(tx_start),.ready(tx_ready),.tx(tx));
reg [255:0] line_buffer;
reg [5:0] line_length;
reg line_error,busy_reply_pending,reset_pending;
reg [511:0] reply_buffer;
reg [5:0] reply_kind;
reg event_wait;
reg[15:0]event_snapshot_id,event_snapshot_crc;
reg[1:0]event_snapshot_level;
reg[2:0]event_snapshot_state;
reg[4:0]event_snapshot_area;
reg[6:0]event_snapshot_body;
reg event_snapshot_pending;
reg [2:0] reply_warmup;
reg [5:0] byte_index;
reg [7:0] byte_candidate;
reg[63:0]byte_group;
reg[2:0]byte_lane;
reg [15:0] status_debug;
reg [3:0] status_state;
reg [7:0] status_settings;
reg status_auto,status_overlay;
reg [2:0] status_ownership;
reg [1:0] status_effective,status_local,status_remote;
reg [6:0] remaining;
wire [7:0] uppercase=(rx_data>="a" && rx_data<="z") ? rx_data-8'd32 : rx_data;
wire reply_busy=(remaining!=0)||!tx_ready||tx_start||busy_reply_pending||reset_pending||event_wait;
// UART字节间隔远大于一个系统周期，先寄存宽组合判断，缩短解析路径。
reg reply_busy_d,text_ready_d,text_open_d,text_full_d,text_empty_d;
always @(posedge clk or posedge rst)begin
 if(rst)begin reply_busy_d<=0;text_ready_d<=0;text_open_d<=0;text_full_d<=0;text_empty_d<=1;end
 else begin
  reply_busy_d<=reply_busy;text_ready_d<=text_ready;text_open_d<=text_open;
  text_full_d<=text_length>=64;text_empty_d<=text_length==0;
 end
end
wire ready_for_control=(next_block_reason!=1);
wire [2:0] image_count=debug_status[14:12];
wire [7:0] argument=line_buffer[7:0];
// 命令匹配提前寄存，拆开长比较与应答选择，满足100MHz时序。
reg [29:0] decoded;
reg [5:0] operation;
integer op_index;
always @(posedge clk or posedge rst)begin
 if(rst)operation<=63;
 else begin
  operation<=63;
  for(op_index=0;op_index<30;op_index=op_index+1)
   if(decoded[op_index])operation<=op_index;
 end
end
always @(posedge clk or posedge rst) begin
 if(rst) decoded<=0;
 else begin
  decoded[0]<=(line_buffer=="PING");
  decoded[1]<=(line_buffer=="NEXT");
  decoded[2]<=(line_length==6 && (line_buffer>>8)=="SHOW ");
  decoded[3]<=(line_buffer=="AUTO ON");
  decoded[4]<=(line_buffer=="AUTO OFF");
  decoded[5]<=(line_buffer=="EMERGENCY ON");
  decoded[6]<=(line_buffer=="EMERGENCY OFF");
  decoded[7]<=(line_length==12 && (line_buffer>>8)=="BRIGHTNESS ");
  decoded[8]<=(line_length==10 && (line_buffer>>8)=="CONTRAST ");
  decoded[9]<=(line_buffer=="ADJUST ON");
  decoded[10]<=(line_buffer=="ADJUST OFF");
  decoded[11]<=(line_buffer=="SELECT BRIGHTNESS");
  decoded[12]<=(line_buffer=="SELECT CONTRAST");
  decoded[13]<=(line_buffer=="OVERLAY ON");
  decoded[14]<=(line_buffer=="OVERLAY OFF");
  decoded[15]<=(line_buffer=="LOCAL");
  decoded[16]<=(line_buffer=="RESET");
  decoded[17]<=(line_buffer=="STATUS");
  decoded[18]<=(line_buffer=="TBEGIN");
  decoded[19]<=(line_length==9 && (line_buffer>>24)=="TCHAR ");
  decoded[20]<=(line_buffer=="TCOMMIT");
  decoded[21]<=(line_buffer=="TDEFAULT");
  decoded[22]<=(GRADED_ALERT_ENABLE && line_length==7 && (line_buffer>>8)=="ALERT ");
  decoded[23]<=(GRADED_ALERT_ENABLE && line_buffer=="ALERT CLEAR");
  decoded[24]<=(EVENT_ENABLE && line_length==19 && (line_buffer>>96)=="EBEGIN ");
  decoded[25]<=(EVENT_ENABLE && line_length==9 && (line_buffer>>24)=="ECHAR ");
  decoded[26]<=(EVENT_ENABLE && line_length==12 && (line_buffer>>32)=="ECOMMIT ");
  decoded[27]<=(EVENT_ENABLE && line_buffer=="EABORT");
  decoded[28]<=(EVENT_ENABLE && line_length==11 && (line_buffer>>32)=="ECLEAR ");
  decoded[29]<=(EVENT_ENABLE && line_buffer=="ESTATUS");
 end
end

function [7:0] hex_ascii;
 input[3:0] v;begin hex_ascii=(v<10)?8'd48+v:8'd55+v;end
endfunction
function[15:0]parse_hex4;input[31:0]chars;
 begin parse_hex4={from_hex(chars[31:24]),from_hex(chars[23:16]),from_hex(chars[15:8]),from_hex(chars[7:0])};end
endfunction
function valid_hex4;input[31:0]chars;
 begin valid_hex4=hex_valid(chars[31:24])&&hex_valid(chars[23:16])&&hex_valid(chars[15:8])&&hex_valid(chars[7:0]);end
endfunction
wire event_header_valid=valid_hex4(line_buffer[95:64])&&line_buffer[63:56]==" "&&
 line_buffer[55:48]>="1"&&line_buffer[55:48]<="3"&&line_buffer[47:40]==" "&&
 hex_valid(line_buffer[39:32])&&hex_valid(line_buffer[31:24])&&line_buffer[23:16]==" "&&
 hex_valid(line_buffer[15:8])&&hex_valid(line_buffer[7:0]);
wire glyph_argument_ok=(line_buffer[23:16]>="0"&&line_buffer[23:16]<="3") &&
 hex_valid(line_buffer[15:8]) && hex_valid(line_buffer[7:0]);
wire [9:0] glyph_argument={line_buffer[17:16],from_hex(line_buffer[15:8]),from_hex(line_buffer[7:0])};
reg header_valid_d,header_counts_d,tail_hex_d,event_glyph_ok_d;
reg[15:0]header_id_d,tail_value_d;
reg[1:0]header_level_d;
reg[4:0]header_area_d;
reg[6:0]header_body_d;
reg[9:0]event_glyph_d;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  header_valid_d<=0;header_counts_d<=0;tail_hex_d<=0;event_glyph_ok_d<=0;
  header_id_d<=0;tail_value_d<=0;header_level_d<=0;header_area_d<=0;header_body_d<=0;event_glyph_d<=0;
 end else begin
  header_valid_d<=event_header_valid;
  header_counts_d<=parse_hex4({16'h3030,line_buffer[39:24]})<=16 && parse_hex4({16'h3030,line_buffer[15:0]})<=64;
  header_id_d<=parse_hex4(line_buffer[95:64]);header_level_d<=line_buffer[49:48];
  header_area_d<={from_hex(line_buffer[39:32]),from_hex(line_buffer[31:24])};
  header_body_d<={from_hex(line_buffer[15:8]),from_hex(line_buffer[7:0])};
  tail_hex_d<=valid_hex4(line_buffer[31:0]);tail_value_d<=parse_hex4(line_buffer[31:0]);
  event_glyph_ok_d<=glyph_argument_ok;event_glyph_d<=glyph_argument;
 end
end
function [3:0] from_hex;
 input[7:0] c;
 begin from_hex=(c>="0"&&c<="9")?c-8'd48:c-8'd55;end
endfunction
function hex_valid;
 input[7:0] c;
 begin hex_valid=(c>="0"&&c<="9")||(c>="A"&&c<="F");end
endfunction
function [2:0] level_value;
 input[2:0] old_level;input[7:0] arg;
 begin
  if(arg=="+")level_value=(old_level<4)?old_level+1'b1:3'd4;
  else if(arg=="-")level_value=(old_level>0)?old_level-1'b1:3'd0;
  else level_value=arg-8'd48;
 end
endfunction
// Reply code -> message ROM, followed by a registered byte selector.
always @(*)begin
reply_buffer=0;case(reply_kind)
5'd0:reply_buffer={"ERR NOTREADY",8'd13,8'd10};
5'd1:reply_buffer={"ERR EMERGENCY",8'd13,8'd10};
5'd2:reply_buffer={"ERR ADJUST",8'd13,8'd10};
5'd3:reply_buffer={"ERR BUSY",8'd13,8'd10};
5'd4:reply_buffer={"ERR NOIMAGE",8'd13,8'd10};
5'd5:reply_buffer={"ERR LINE",8'd13,8'd10};
5'd6:reply_buffer={"PONG",8'd13,8'd10};
5'd7:reply_buffer={"OK NEXT",8'd13,8'd10};
5'd8:reply_buffer={"ERR RANGE",8'd13,8'd10};
5'd9:reply_buffer={"OK SHOW",8'd13,8'd10};
5'd10:reply_buffer={"OK AUTO",8'd13,8'd10};
5'd11:reply_buffer={"OK EMERGENCY",8'd13,8'd10};
5'd12:reply_buffer={"OK BRIGHTNESS",8'd13,8'd10};
5'd13:reply_buffer={"OK CONTRAST",8'd13,8'd10};
5'd14:reply_buffer={"OK ADJUST",8'd13,8'd10};
5'd15:reply_buffer={"OK SELECT",8'd13,8'd10};
5'd16:reply_buffer={"OK OVERLAY",8'd13,8'd10};
5'd17:reply_buffer={"OK LOCAL",8'd13,8'd10};
5'd18:reply_buffer={"OK RESET",8'd13,8'd10};
5'd19:reply_buffer={"OK ALERT",8'd13,8'd10};
5'd27:reply_buffer={"OK CLEAR",8'd13,8'd10};
5'd20:reply_buffer={"OK TBEGIN",8'd13,8'd10};
5'd21:reply_buffer={"OK TDEFAULT",8'd13,8'd10};
5'd22:reply_buffer={"ERR TEXT",8'd13,8'd10};
5'd23:reply_buffer={"OK TCHAR",8'd13,8'd10};
5'd24:reply_buffer={"OK TCOMMIT",8'd13,8'd10};
5'd25:reply_buffer={"ERR CMD",8'd13,8'd10};
5'd26:begin if(EXTENDED_STATUS)reply_buffer={"STATUS D=",hex_ascii(status_debug[15:12]),hex_ascii(status_debug[11:8]),
 hex_ascii(status_debug[7:4]),hex_ascii(status_debug[3:0])," S=",hex_ascii(status_state),
 " P=",hex_ascii(status_settings[7:4]),hex_ascii(status_settings[3:0]),
 " A=",hex_ascii({3'b0,status_auto})," O=",hex_ascii({3'b0,status_overlay}),
 " R=",hex_ascii({1'b0,status_ownership}),8'd13,8'd10};
 else reply_buffer={"STATUS D=",hex_ascii(status_debug[15:12]),hex_ascii(status_debug[11:8]),
 hex_ascii(status_debug[7:4]),hex_ascii(status_debug[3:0])," S=",hex_ascii(status_state),
 " P=",hex_ascii(status_settings[7:4]),hex_ascii(status_settings[3:0]),8'd13,8'd10};
 if(EXTENDED_STATUS&&GRADED_ALERT_ENABLE)reply_buffer={"STATUS D=",hex_ascii(status_debug[15:12]),hex_ascii(status_debug[11:8]),
 hex_ascii(status_debug[7:4]),hex_ascii(status_debug[3:0])," S=",hex_ascii(status_state),
 " P=",hex_ascii(status_settings[7:4]),hex_ascii(status_settings[3:0]),
 " A=",hex_ascii({3'b0,status_auto})," O=",hex_ascii({3'b0,status_overlay}),
 " R=",hex_ascii({1'b0,status_ownership})," E=",hex_ascii({2'b0,status_effective}),
 " B=",hex_ascii({2'b0,status_local})," M=",hex_ascii({2'b0,status_remote}),8'd13,8'd10};end
6'd28:reply_buffer={"EVENT I=",hex_ascii(event_snapshot_id[15:12]),hex_ascii(event_snapshot_id[11:8]),hex_ascii(event_snapshot_id[7:4]),hex_ascii(event_snapshot_id[3:0]),
 " L=",hex_ascii({2'b0,event_snapshot_level})," S=",hex_ascii({1'b0,event_snapshot_state}),
 " C=",hex_ascii(event_snapshot_crc[15:12]),hex_ascii(event_snapshot_crc[11:8]),hex_ascii(event_snapshot_crc[7:4]),hex_ascii(event_snapshot_crc[3:0]),
 " A=",hex_ascii({3'b0,event_snapshot_area[4]}),hex_ascii(event_snapshot_area[3:0]),
 " T=",hex_ascii({1'b0,event_snapshot_body[6:4]}),hex_ascii(event_snapshot_body[3:0]),
 " P=",hex_ascii({3'b0,event_snapshot_pending}),8'd13,8'd10};
6'd32:reply_buffer={"OK EBEGIN",8'd13,8'd10};
6'd33:reply_buffer={"OK ECHAR",8'd13,8'd10};
6'd34:reply_buffer={"OK ACCEPT",8'd13,8'd10};
6'd35:reply_buffer={"OK DUP",8'd13,8'd10};
6'd36:reply_buffer={"OK ABORT",8'd13,8'd10};
6'd37:reply_buffer={"OK ECLEAR",8'd13,8'd10};
6'd38:reply_buffer={"ERR EVENTBUSY",8'd13,8'd10};
6'd39:reply_buffer={"ERR EVENT",8'd13,8'd10};
6'd40:reply_buffer={"ERR LENGTH",8'd13,8'd10};
6'd41:reply_buffer={"ERR CRC",8'd13,8'd10};
6'd42:reply_buffer={"ERR ID",8'd13,8'd10};
6'd43:reply_buffer={"ERR RANGE",8'd13,8'd10};
6'd44:reply_buffer={"ERR NOTREADY",8'd13,8'd10};
6'd45:reply_buffer={"ERR NOEVENT",8'd13,8'd10};
6'd46:reply_buffer={"ERR NOIMAGE",8'd13,8'd10};
default:reply_buffer=0;endcase end
always @(posedge clk or posedge rst)begin
 if(rst)begin byte_index<=0;byte_candidate<=0;byte_group<=0;byte_lane<=0;end
 else begin
  byte_index<=remaining-1'b1;
  byte_group<=reply_buffer[{byte_index[5:3],6'b000000}+:64];byte_lane<=byte_index[2:0];
  byte_candidate<=byte_group[{byte_lane,3'b000}+:8];
 end
end
task reply;
 input[5:0] kind;input[6:0] length;
 begin reply_kind<=kind;remaining<=length;reply_warmup<=6;end
endtask
task send_event;input[2:0]code;
 begin event_cmd_valid<=1;event_cmd<=code;event_wait<=1;end
endtask
task emit;
 input[3:0] code;input[2:0] value;
 begin command_valid<=1;command_code<=code;command_value<=value;end
endtask
task block_reply;
 input[2:0] reason;
 begin
  case(reason)
   1:reply(5'd0,7'd14);
   2:reply(5'd1,7'd15);
   3:reply(5'd2,7'd12);
   4:reply(5'd3,7'd10);
   default:reply(5'd4,7'd13);
  endcase
 end
endtask
always @(posedge clk or posedge rst) begin
 if(rst) begin
  line_buffer<=0;line_length<=0;line_error<=0;busy_reply_pending<=0;
  reply_kind<=0;reply_warmup<=0;remaining<=0;
  status_debug<=0;status_state<=0;status_settings<=0;status_auto<=0;status_overlay<=0;status_ownership<=0;tx_data<=0;tx_start<=0;next_pulse<=0;
  status_effective<=0;status_local<=0;status_remote<=0;
  event_wait<=0;event_cmd_valid<=0;event_cmd<=0;event_id<=0;event_crc<=0;
  event_level<=0;event_area<=0;event_body<=0;event_glyph<=0;
  event_snapshot_id<=0;event_snapshot_crc<=0;event_snapshot_level<=0;event_snapshot_state<=0;
  event_snapshot_area<=0;event_snapshot_body<=0;event_snapshot_pending<=0;
  command_valid<=0;command_code<=0;command_value<=0;text_glyph<=0;reset_pending<=0;soft_reset<=0;
  overlay_override<=0;overlay_value<=1;adjust_override<=0;adjust_value<=0;
  select_override<=0;select_value<=0;
 end else begin
  tx_start<=0;next_pulse<=0;command_valid<=0;soft_reset<=0;event_cmd_valid<=0;
  if(event_wait&&event_result_valid)begin
   event_wait<=0;
   case(event_result)
    0:reply(32,11);1:reply(33,10);2:reply(34,11);3:reply(35,8);
    4:reply(36,10);5:reply(37,11);6:reply(38,15);7:reply(39,11);
    8:reply(40,12);9:reply(41,9);10:reply(42,8);11:reply(43,11);
    12:reply(44,14);13:reply(45,13);14:reply(46,13);default:reply(39,11);
   endcase
  end
  if(reply_warmup!=0)reply_warmup<=reply_warmup-1'b1;
  if(remaining!=0 && reply_warmup==0 && tx_ready && !tx_start)begin
   tx_data<=byte_candidate;tx_start<=1;remaining<=remaining-1'b1;
  end
  if(remaining==0 && tx_ready && !tx_start && busy_reply_pending && !reset_pending)begin
   reply(5'd3,7'd10);busy_reply_pending<=0;
  end
  // 先把确认信息完整发送，再复位整机，避免截断应答。
  if(remaining==0 && tx_ready && !tx_start && reset_pending)begin
   soft_reset<=1;reset_pending<=0;
  end
  if(rx_error)begin line_buffer<=0;line_length<=0;line_error<=1;end
  else if(rx_valid)begin
   if(rx_data==13 || rx_data==10)begin
    if(line_length!=0 || line_error)begin
     if(reply_busy_d)busy_reply_pending<=1;
     else if(line_error)reply(5'd5,7'd10);
     else case(operation)
     0:reply(5'd6,7'd6);
     1:begin
      if(next_block_reason!=0)block_reply(next_block_reason);
      else begin next_pulse<=1;reply(5'd7,7'd9);end
     end
     2:begin
      if(argument<"1" || argument>"3")reply(5'd8,7'd11);
      else if(next_block_reason!=0)block_reply(next_block_reason);
      else if((argument-8'd48)>image_count)block_reply(5);
      else begin emit(2,argument-8'd49);reply(5'd9,7'd9);end
     end
     3,4:begin
      if(!ready_for_control)block_reply(1);
      else if(debug_status[0])block_reply(2);
      else if(operation==3 && image_count<2)block_reply(5);
      else begin emit(3,operation==3);reply(5'd10,7'd9);end
     end
     5,6:begin
      if(EVENT_ENABLE&&event_busy)reply(38,15);
      else if(!ready_for_control)block_reply(1);
      else if(operation==5 && image_count<4)block_reply(5);
      else begin emit(4,operation==5);reply(5'd11,7'd14);end
     end
     7,8:begin
      if(debug_status[0])block_reply(2);
      else if(!((argument>="0" && argument<="4") || argument=="+" || argument=="-"))
       reply(5'd8,7'd11);
      else if(operation==7)begin
       emit(5,level_value(picture_settings[5:3],argument));reply(5'd12,7'd15);
      end else begin emit(6,level_value(picture_settings[2:0],argument));reply(5'd13,7'd13);end
     end
     9,10:begin
      if(debug_status[0])block_reply(2);
      else begin adjust_override<=1;adjust_value<=operation==9;reply(5'd14,7'd11);end
     end
     11,12:begin
      if(debug_status[0])block_reply(2);
      else begin select_override<=1;select_value<=operation==12;reply(5'd15,7'd11);end
     end
     13,14:begin
      overlay_override<=1;overlay_value<=operation==13;reply(5'd16,7'd12);
     end
     15:begin
      overlay_override<=0;adjust_override<=0;select_override<=0;reply(5'd17,7'd10);
     end
     16:begin
      reset_pending<=1;reply(5'd18,7'd10);
     end
     22:begin
      if(EVENT_ENABLE&&event_busy)reply(38,15);
      else if(!ready_for_control)block_reply(1);
      else if(argument<"1"||argument>"3")reply(5'd8,7'd11);
      else if(argument>"1"&&image_count<4)block_reply(5);
      else begin emit(13,argument-8'd48);reply(5'd19,7'd10);end
     end
     23:begin
      if(EVENT_ENABLE&&event_busy)reply(38,15);
      else begin emit(13,0);reply(5'd27,7'd10);end
     end
     24:begin
      if(!header_valid_d||!header_counts_d)reply(43,11);
      else begin
       event_id<=header_id_d;event_level<=header_level_d;
       event_area<=header_area_d;event_body<=header_body_d;send_event(1);
      end
     end
     25:begin
      if(!event_glyph_ok_d)reply(43,11);
      else begin event_glyph<=event_glyph_d;send_event(2);end
     end
     26:begin
      if(!tail_hex_d)reply(43,11);
      else begin event_crc<=tail_value_d;send_event(3);end
     end
     27:send_event(4);
     28:begin
      if(!tail_hex_d)reply(43,11);
      else begin event_id<=tail_value_d;send_event(5);end
     end
     29:begin
      event_snapshot_id<=event_active_id;event_snapshot_crc<=event_active_crc;
      event_snapshot_level<=event_active_level;event_snapshot_state<=event_state;
      event_snapshot_area<=event_active_area;event_snapshot_body<=event_active_body;
      event_snapshot_pending<=event_busy;reply(28,43);
     end
     18,19,20,21:begin
      if(!text_ready_d) block_reply(4);
      else if(operation==18)begin emit(7,0);reply(5'd20,7'd11);end
      else if(operation==21)begin emit(10,0);reply(5'd21,7'd13);end
      else if(!text_open_d)reply(5'd22,7'd10);
      else if(operation==19)begin
       if(!glyph_argument_ok||glyph_argument>=607||text_full_d)reply(5'd8,7'd11);
       else begin text_glyph<=glyph_argument;emit(8,0);reply(5'd23,7'd10);end
      end else if(text_empty_d)reply(5'd8,7'd11);
      else begin emit(9,0);reply(5'd24,7'd12);end
     end
     17:begin
      status_debug<=debug_status;status_state<=state_code;status_settings<=picture_settings;
      status_auto<=auto_status;status_overlay<=overlay_status;
      status_ownership<={overlay_override,adjust_override,select_override};
      status_effective<=effective_alert;status_local<=local_alert;status_remote<=remote_alert;
      reply(5'd26,(EXTENDED_STATUS&&GRADED_ALERT_ENABLE)?7'd48:EXTENDED_STATUS?7'd36:7'd24);
     end
     default:reply(5'd25,7'd9);
     endcase
    end
    line_buffer<=0;line_length<=0;line_error<=0;
   end else if(!line_error)begin
    if(line_length==32 || rx_data<32 || rx_data>126)line_error<=1;
    else begin line_buffer<={line_buffer[247:0],uppercase};line_length<=line_length+1'b1;end
   end
  end
 end
end
endmodule

// 字幕双缓冲：写入空闲银行，提交后等待视频帧边界确认再允许改写。
// 跨域请求及应答使用toggle握手；银行、长度和字符在握手期间保持稳定。
module remote_text_buffer(
 input write_clk,write_rst,command_valid,
 input [3:0] command_code,input [9:0] glyph,
 output ready,output reg transaction_open,output reg [6:0] length,
 input video_clk,video_rst,frame_start,input [5:0] read_index,
 output reg active,output reg changed,output [9:0] read_glyph
);
reg [9:0] characters[0:127];
reg write_bank,request_toggle,requested_bank,requested_active;
reg [6:0] requested_length;
reg ack_sync0,ack_sync1;
reg request_sync0,request_sync1,ack_toggle,active_bank;
reg [6:0] active_length;
assign ready=(request_toggle==ack_sync1);
assign read_glyph=(active && {1'b0,read_index}<active_length)?
 characters[{active_bank,read_index}]:10'd0;
always @(posedge write_clk or posedge write_rst)begin
 if(write_rst)begin
  write_bank<=1;request_toggle<=0;requested_bank<=0;requested_active<=0;
  requested_length<=0;transaction_open<=0;length<=0;ack_sync0<=0;ack_sync1<=0;
 end else begin
  ack_sync0<=ack_toggle;ack_sync1<=ack_sync0;
  if(command_valid&&ready)case(command_code)
   7:begin write_bank<=~requested_bank;length<=0;transaction_open<=1;end
   8:if(transaction_open&&length<64)begin
      characters[{write_bank,length[5:0]}]<=glyph;length<=length+1'b1;
     end
   9:if(transaction_open&&length!=0)begin
      requested_bank<=write_bank;requested_length<=length;requested_active<=1;
      request_toggle<=~request_toggle;transaction_open<=0;
     end
   10:begin requested_active<=0;request_toggle<=~request_toggle;transaction_open<=0;end
  endcase
 end
end
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin
  request_sync0<=0;request_sync1<=0;ack_toggle<=0;active_bank<=0;active<=0;active_length<=0;changed<=0;
 end else begin
  request_sync0<=request_toggle;request_sync1<=request_sync0;changed<=0;
  if(frame_start && request_sync1!=ack_toggle)begin
   active_bank<=requested_bank;active_length<=requested_length;active<=requested_active;
   ack_toggle<=request_sync1;changed<=1;
  end
 end
end
endmodule

module uart_rx_8n1 #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer BAUD=115200
)(input clk,rst,rx,output reg [7:0] data,output reg valid,framing_error);
localparam integer DIV=(CLK_FREQ_HZ+BAUD/2)/BAUD;
reg rx_sync0,rx_sync1;
reg [31:0] ticks;
reg [2:0] bit_index;
reg [7:0] shift;
reg [2:0] state;
localparam IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        rx_sync0<=1;rx_sync1<=1;ticks<=0;bit_index<=0;shift<=0;
        state<=IDLE;data<=0;valid<=0;framing_error<=0;
    end else begin
        rx_sync0<=rx;rx_sync1<=rx_sync0;valid<=0;framing_error<=0;
        case(state)
            IDLE:if(!rx_sync1) begin ticks<=DIV/2-1;state<=START;end
            START:if(ticks!=0) ticks<=ticks-1'b1;
                else if(rx_sync1) state<=IDLE;
                else begin ticks<=DIV-1;bit_index<=0;state<=DATA;end
            DATA:if(ticks!=0) ticks<=ticks-1'b1;
                else begin
                    shift[bit_index]<=rx_sync1;ticks<=DIV-1;
                    if(bit_index==7) state<=STOP;else bit_index<=bit_index+1'b1;
                end
            STOP:if(ticks!=0) ticks<=ticks-1'b1;
                else if(rx_sync1) begin data<=shift;valid<=1;state<=IDLE;end
                else begin framing_error<=1;state<=RECOVER;end
            // 错误停止位/持续低电平后先等线路恢复，不把break拆成多个字符。
            RECOVER:if(rx_sync1) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
end
endmodule

module uart_tx_8n1 #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer BAUD=115200
)(input clk,rst,input [7:0] data,input start,output ready,output tx);
localparam integer DIV=(CLK_FREQ_HZ+BAUD/2)/BAUD;
reg [31:0] ticks;
reg [3:0] bit_index;
reg [9:0] frame;
reg busy;
assign ready=!busy;
assign tx=busy?frame[bit_index]:1'b1;
always @(posedge clk or posedge rst) begin
    if(rst) begin ticks<=0;bit_index<=0;frame<=10'h3FF;busy<=0;end
    else if(!busy) begin
        if(start) begin frame<={1'b1,data,1'b0};ticks<=DIV-1;bit_index<=0;busy<=1;end
    end else if(ticks!=0) ticks<=ticks-1'b1;
    else if(bit_index==9) busy<=0;
    else begin ticks<=DIV-1;bit_index<=bit_index+1'b1;end
end
endmodule


