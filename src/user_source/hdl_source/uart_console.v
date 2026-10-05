// 文件：uart_console.v
// 职责：串口命令解析、状态快照及电脑控制；8N1，大小写不敏感。
// 帧缓存、图像和音频处理仍在FPGA内部；串口仅传输人工命令。
module uart_console #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer BAUD=115200,
    parameter integer EXTENDED_STATUS=0
)(
    input clk,rst,rx,output tx,
    input [2:0] next_block_reason,
    input [15:0] debug_status,
    input [3:0] state_code,
    input [7:0] picture_settings,
    input auto_status,overlay_status,text_ready,text_open,
    input [6:0] text_length,
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
reg [6:0] remaining;
wire [7:0] uppercase=(rx_data>="a" && rx_data<="z") ? rx_data-8'd32 : rx_data;
wire reply_busy=(remaining!=0)||!tx_ready||tx_start||busy_reply_pending||reset_pending;
wire ready_for_control=(next_block_reason!=1);
wire [2:0] image_count=debug_status[14:12];
wire [7:0] argument=line_buffer[7:0];
// 命令匹配提前寄存，拆开长比较与应答选择，满足100MHz时序。
reg [21:0] decoded;
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
 end
end

function [7:0] hex_ascii;
 input[3:0] v;begin hex_ascii=(v<10)?8'd48+v:8'd55+v;end
endfunction
function [3:0] from_hex;
 input[7:0] c;
 begin from_hex=(c>="0"&&c<="9")?c-8'd48:c-8'd55;end
endfunction
function hex_valid;
 input[7:0] c;
 begin hex_valid=(c>="0"&&c<="9")||(c>="A"&&c<="F");end
endfunction
wire glyph_argument_ok=(line_buffer[23:16]>="0"&&line_buffer[23:16]<="3") &&
 hex_valid(line_buffer[15:8]) && hex_valid(line_buffer[7:0]);
wire [9:0] glyph_argument={line_buffer[17:16],from_hex(line_buffer[15:8]),from_hex(line_buffer[7:0])};
function [2:0] level_value;
 input[2:0] old_level;input[7:0] arg;
 begin
  if(arg=="+")level_value=(old_level<4)?old_level+1'b1:3'd4;
  else if(arg=="-")level_value=(old_level>0)?old_level-1'b1:3'd0;
  else level_value=arg-8'd48;
 end
endfunction
task reply;
 input[511:0] text;input[6:0] length;
 begin reply_buffer<=text;remaining<=length;end
endtask
task emit;
 input[3:0] code;input[2:0] value;
 begin command_valid<=1;command_code<=code;command_value<=value;end
endtask
task block_reply;
 input[2:0] reason;
 begin
  case(reason)
   1:reply({"ERR NOTREADY",8'd13,8'd10},14);
   2:reply({"ERR EMERGENCY",8'd13,8'd10},15);
   3:reply({"ERR ADJUST",8'd13,8'd10},12);
   4:reply({"ERR BUSY",8'd13,8'd10},10);
   default:reply({"ERR NOIMAGE",8'd13,8'd10},13);
  endcase
 end
endtask
always @(posedge clk or posedge rst) begin
 if(rst) begin
  line_buffer<=0;line_length<=0;line_error<=0;busy_reply_pending<=0;
  reply_buffer<=0;remaining<=0;tx_data<=0;tx_start<=0;next_pulse<=0;
  command_valid<=0;command_code<=0;command_value<=0;text_glyph<=0;reset_pending<=0;soft_reset<=0;
  overlay_override<=0;overlay_value<=1;adjust_override<=0;adjust_value<=0;
  select_override<=0;select_value<=0;
 end else begin
  tx_start<=0;next_pulse<=0;command_valid<=0;soft_reset<=0;
  if(remaining!=0 && tx_ready && !tx_start)begin
   tx_data<=reply_buffer[(remaining-1'b1)*8+:8];tx_start<=1;remaining<=remaining-1'b1;
  end
  if(remaining==0 && tx_ready && !tx_start && busy_reply_pending && !reset_pending)begin
   reply({"ERR BUSY",8'd13,8'd10},10);busy_reply_pending<=0;
  end
  // 先把确认信息完整发送，再复位整机，避免截断应答。
  if(remaining==0 && tx_ready && !tx_start && reset_pending)begin
   soft_reset<=1;reset_pending<=0;
  end
  if(rx_error)begin line_buffer<=0;line_length<=0;line_error<=1;end
  else if(rx_valid)begin
   if(rx_data==13 || rx_data==10)begin
    if(line_length!=0 || line_error)begin
     if(reply_busy)busy_reply_pending<=1;
     else if(line_error)reply({"ERR LINE",8'd13,8'd10},10);
     else if(decoded[0])reply({"PONG",8'd13,8'd10},6);
     else if(decoded[1])begin
      if(next_block_reason!=0)block_reply(next_block_reason);
      else begin next_pulse<=1;reply({"OK NEXT",8'd13,8'd10},9);end
     end else if(decoded[2])begin
      if(argument<"1" || argument>"3")reply({"ERR RANGE",8'd13,8'd10},11);
      else if(next_block_reason!=0)block_reply(next_block_reason);
      else if((argument-8'd48)>image_count)block_reply(5);
      else begin emit(2,argument-8'd49);reply({"OK SHOW",8'd13,8'd10},9);end
     end else if(decoded[3] || decoded[4])begin
      if(!ready_for_control)block_reply(1);
      else if(debug_status[0])block_reply(2);
      else if(decoded[3] && image_count<2)block_reply(5);
      else begin emit(3,decoded[3]);reply({"OK AUTO",8'd13,8'd10},9);end
     end else if(decoded[5] || decoded[6])begin
      if(!ready_for_control)block_reply(1);
      else if(decoded[5] && image_count<4)block_reply(5);
      else begin emit(4,decoded[5]);reply({"OK EMERGENCY",8'd13,8'd10},14);end
     end else if((decoded[7]) ||
                 (decoded[8]))begin
      if(debug_status[0])block_reply(2);
      else if(!((argument>="0" && argument<="4") || argument=="+" || argument=="-"))
       reply({"ERR RANGE",8'd13,8'd10},11);
      else if(decoded[7])begin
       emit(5,level_value(picture_settings[5:3],argument));reply({"OK BRIGHTNESS",8'd13,8'd10},15);
      end else begin emit(6,level_value(picture_settings[2:0],argument));reply({"OK CONTRAST",8'd13,8'd10},13);end
     end else if(decoded[9] || decoded[10])begin
      if(debug_status[0])block_reply(2);
      else begin adjust_override<=1;adjust_value<=decoded[9];reply({"OK ADJUST",8'd13,8'd10},11);end
     end else if(decoded[11] || decoded[12])begin
      if(debug_status[0])block_reply(2);
      else begin select_override<=1;select_value<=decoded[12];reply({"OK SELECT",8'd13,8'd10},11);end
     end else if(decoded[13] || decoded[14])begin
      overlay_override<=1;overlay_value<=decoded[13];reply({"OK OVERLAY",8'd13,8'd10},12);
     end else if(decoded[15])begin
      overlay_override<=0;adjust_override<=0;select_override<=0;reply({"OK LOCAL",8'd13,8'd10},10);
     end else if(decoded[16])begin
      reset_pending<=1;reply({"OK RESET",8'd13,8'd10},10);
     end else if(decoded[18]||decoded[19]||decoded[20]||decoded[21])begin
      if(!text_ready) block_reply(4);
      else if(decoded[18])begin emit(7,0);reply({"OK TBEGIN",8'd13,8'd10},11);end
      else if(decoded[21])begin emit(10,0);reply({"OK TDEFAULT",8'd13,8'd10},13);end
      else if(!text_open)reply({"ERR TEXT",8'd13,8'd10},10);
      else if(decoded[19])begin
       if(!glyph_argument_ok||glyph_argument>=598||text_length>=64)reply({"ERR RANGE",8'd13,8'd10},11);
       else begin text_glyph<=glyph_argument;emit(8,0);reply({"OK TCHAR",8'd13,8'd10},10);end
      end else if(text_length==0)reply({"ERR RANGE",8'd13,8'd10},11);
      else begin emit(9,0);reply({"OK TCOMMIT",8'd13,8'd10},12);end
     end else if(decoded[17])begin
      if(EXTENDED_STATUS)reply({"STATUS D=",hex_ascii(debug_status[15:12]),hex_ascii(debug_status[11:8]),
       hex_ascii(debug_status[7:4]),hex_ascii(debug_status[3:0])," S=",hex_ascii(state_code),
       " P=",hex_ascii(picture_settings[7:4]),hex_ascii(picture_settings[3:0]),
       " A=",hex_ascii({3'b0,auto_status})," O=",hex_ascii({3'b0,overlay_status}),
       " R=",hex_ascii({1'b0,overlay_override,adjust_override,select_override}),8'd13,8'd10},36);
      else reply({"STATUS D=",hex_ascii(debug_status[15:12]),hex_ascii(debug_status[11:8]),
       hex_ascii(debug_status[7:4]),hex_ascii(debug_status[3:0])," S=",hex_ascii(state_code),
       " P=",hex_ascii(picture_settings[7:4]),hex_ascii(picture_settings[3:0]),8'd13,8'd10},24);
     end else reply({"ERR CMD",8'd13,8'd10},9);
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

