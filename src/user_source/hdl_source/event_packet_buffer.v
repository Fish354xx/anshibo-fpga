// 事件事务：元数据+字形编号通过CRC16-CCITT-FALSE校验后提交。
// 双银行保持已显示内容不可改写，视频帧确认前禁止新写事务。
module event_packet_buffer #(
 parameter integer FONT_COUNT=607
)(
 input clk,rst,cmd_valid,input[2:0]cmd,
 input[15:0]event_id,check_crc,input[1:0]level,
 input[4:0]area_length,input[6:0]body_length,input[9:0]glyph,
 input ready,major_available,legacy_change,input[1:0]local_level,
 output reg result_valid,output reg[3:0]result,
 output reg apply_valid,output reg[1:0]apply_level,
 output reg active_valid,output reg[15:0]active_id,active_crc,active_generation,
 output reg[1:0]active_level,output reg[4:0]active_area_length,
 output reg[6:0]active_body_length,output busy,
 output[2:0]event_state,
 input video_clk,video_rst,install,
 input shown_remote,input[15:0]shown_id,shown_generation,input[1:0]shown_level,
 output video_pending,output pending_bank,
 output[15:0]pending_id,pending_generation,output[1:0]pending_level,
 output[4:0]pending_area_length,output[6:0]pending_body_length,
 input read_bank,input[6:0]read_index,output[9:0]read_glyph
);
localparam IDLE=0,HEADER=1,CHAR_LOW=2,DUP_STAGE=3,DUP_WAIT=4,DUP_CAPTURE=5,DUP_ACTIVE=6,DUP_COMPARE=7;
reg[2:0]state;
reg[9:0]characters[0:159];
reg staging_open,staging_bank,current_bank;
reg[15:0]staging_id,crc;
reg[1:0]staging_level;
reg[4:0]staging_area;
reg[6:0]staging_body,received,compare_index,expected_count;
reg[2:0]header_index;
reg[7:0]low_byte;
reg[9:0]compare_word;
reg[7:0]compare_address,write_address;
reg[9:0]compare_read_data;
reg request_toggle,ack_toggle,ack_sync0,ack_sync1,request_sync0,request_sync1;
reg requested_bank;
reg[15:0]requested_id;
reg[15:0]requested_generation,shown_generation_sync0,shown_generation_sync1;
reg[1:0]requested_level;
reg[4:0]requested_area;
reg[6:0]requested_body;
reg shown_sync0,shown_sync1;
reg[15:0]shown_id_sync0,shown_id_sync1;
reg[1:0]shown_level_sync0,shown_level_sync1;
assign busy=(request_toggle!=ack_sync1);
assign video_pending=(request_sync1!=ack_toggle);
assign pending_bank=requested_bank;assign pending_id=requested_id;
assign pending_generation=requested_generation;
assign pending_level=requested_level;assign pending_area_length=requested_area;
assign pending_body_length=requested_body;
wire[7:0]read_address=(read_bank?8'd80:8'd0)+read_index;
assign read_glyph=(read_index<80)?characters[read_address]:10'd0;
assign event_state=!active_valid?0:busy?1:
 (shown_sync1&&shown_id_sync1==active_id&&shown_level_sync1==active_level&&shown_generation_sync1==active_generation)?2:
 (local_level!=0&&local_level>=active_level)?3:1;
function[15:0]crc_byte;input[15:0]old_crc;input[7:0]data;
 reg[15:0]value;integer n;
 begin value=old_crc^{data,8'd0};
  for(n=0;n<8;n=n+1)value=value[15]?(value<<1)^16'h1021:(value<<1);
  crc_byte=value;
 end
endfunction
wire[7:0]compare_offset=(compare_index<staging_area)?compare_index:8'd16+compare_index-staging_area;
always @(posedge clk)compare_read_data<=characters[compare_address];
task response;input[3:0]code;begin result<=code;result_valid<=1;end endtask
task commit_new;
begin
 active_valid<=1;active_id<=staging_id;active_level<=staging_level;active_crc<=crc;
 active_generation<=active_generation+1'b1;requested_generation<=active_generation+1'b1;
 active_area_length<=staging_area;active_body_length<=staging_body;
 current_bank<=staging_bank;staging_open<=0;
 requested_bank<=staging_bank;requested_id<=staging_id;requested_level<=staging_level;
 requested_area<=staging_area;requested_body<=staging_body;
 request_toggle<=~request_toggle;apply_valid<=1;apply_level<=staging_level;response(2);
end endtask
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=IDLE;staging_open<=0;staging_bank<=1;current_bank<=0;
  staging_id<=0;staging_level<=0;staging_area<=0;staging_body<=0;received<=0;crc<=16'hFFFF;
  expected_count<=0;
  header_index<=0;low_byte<=0;compare_index<=0;compare_word<=0;
  compare_address<=0;write_address<=0;
  request_toggle<=0;requested_bank<=0;requested_id<=0;requested_level<=0;requested_area<=0;requested_body<=0;
  ack_sync0<=0;ack_sync1<=0;result_valid<=0;result<=0;apply_valid<=0;apply_level<=0;
  active_valid<=0;active_id<=0;active_crc<=0;active_level<=0;active_area_length<=0;active_body_length<=0;
  shown_sync0<=0;shown_sync1<=0;shown_id_sync0<=0;shown_id_sync1<=0;shown_level_sync0<=0;shown_level_sync1<=0;
  active_generation<=0;requested_generation<=0;shown_generation_sync0<=0;shown_generation_sync1<=0;
 end else begin
  ack_sync0<=ack_toggle;ack_sync1<=ack_sync0;
  shown_sync0<=shown_remote;shown_sync1<=shown_sync0;
  shown_id_sync0<=shown_id;shown_id_sync1<=shown_id_sync0;
  shown_level_sync0<=shown_level;shown_level_sync1<=shown_level_sync0;
  shown_generation_sync0<=shown_generation;shown_generation_sync1<=shown_generation_sync0;
  result_valid<=0;apply_valid<=0;
  if(legacy_change)active_valid<=0;
  case(state)
   HEADER:begin
    case(header_index)
     0:crc<=crc_byte(crc,staging_id[15:8]);
     1:crc<=crc_byte(crc,staging_id[7:0]);
     2:crc<=crc_byte(crc,{6'd0,staging_level});
     3:crc<=crc_byte(crc,{3'd0,staging_area});
     4:begin crc<=crc_byte(crc,{1'b0,staging_body});state<=IDLE;response(0);end
    endcase header_index<=header_index+1'b1;
   end
   CHAR_LOW:begin crc<=crc_byte(crc,low_byte);state<=IDLE;response(1);end
   DUP_STAGE:begin compare_address<=(staging_bank?80:0)+compare_offset;state<=DUP_WAIT;end
   DUP_WAIT:state<=DUP_CAPTURE;
   DUP_CAPTURE:begin compare_word<=compare_read_data;compare_address<=(current_bank?80:0)+compare_offset;state<=DUP_ACTIVE;end
   DUP_ACTIVE:state<=DUP_COMPARE;
   DUP_COMPARE:begin
    if(compare_word!=compare_read_data)begin state<=IDLE;response(10);end
    else if(compare_index+1==expected_count)begin state<=IDLE;staging_open<=0;response(3);end
    else begin compare_index<=compare_index+1'b1;state<=DUP_STAGE;end
   end
   default:if(cmd_valid)begin
    if(cmd==5)begin // Targeted clear may cancel an accepted but not yet displayed event.
     if(!active_valid)response(13);
     else if(event_id!=active_id)response(10);
     else begin active_valid<=0;active_level<=0;apply_valid<=1;apply_level<=0;response(5);end
    end else if(busy)response(6);
    else case(cmd)
     1:begin
      if(!ready)response(12);
      else if(level<1||level>3||area_length==0||area_length>16||body_length==0||body_length>64)response(11);
      else if(level>=2&&!major_available)response(14);
      else begin
       staging_open<=1;staging_bank<=~current_bank;received<=0;
       write_address<=current_bank?0:80;
       staging_id<=event_id;staging_level<=level;staging_area<=area_length;staging_body<=body_length;
       expected_count<=area_length+body_length;
       crc<=16'hFFFF;header_index<=0;state<=HEADER;
      end
     end
     2:begin
      if(!staging_open)response(7);
      else if(received>=expected_count)response(8);
      else if(glyph>=FONT_COUNT)response(11);
      else begin
       characters[write_address]<=glyph;received<=received+1'b1;
       write_address<=(received+1==staging_area)?(staging_bank?96:16):write_address+1'b1;
       crc<=crc_byte(crc,{6'd0,glyph[9:8]});low_byte<=glyph[7:0];state<=CHAR_LOW;
      end
     end
     3:begin
      if(!staging_open)response(7);
      else if(received!=expected_count)response(8);
      else if(check_crc!=crc)response(9);
      else if(active_valid&&staging_id==active_id)begin
       if(staging_level!=active_level||staging_area!=active_area_length||staging_body!=active_body_length||crc!=active_crc)response(10);
       else begin compare_index<=0;state<=DUP_STAGE;end
      end else commit_new();
     end
     4:begin staging_open<=0;response(4);end
     default:response(11);
    endcase
   end
  endcase
 end
end
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin request_sync0<=0;request_sync1<=0;ack_toggle<=0;end
 else begin
  request_sync0<=request_toggle;request_sync1<=request_sync0;
  if(install&&video_pending)ack_toggle<=request_sync1;
 end
end
endmodule

// 当前远程画面不可被上传中的新银行覆盖。隐藏事件可安装，但显示回执
// 仅在该事件成为实际显示来源、且首个有效像素到达后产生。
module event_view_control(
 input clk,rst,frame_start,first_pixel,
 input[1:0]requested_level,current_level,
 input requested_remote,packet_valid,major_ready,restore_ready,
 input pending,pending_bank,input[15:0]pending_id,pending_generation,input[1:0]pending_level,
 input[4:0]pending_area,input[6:0]pending_body,
 output install,advance_allowed,
 output reg frame_remote,read_bank,
 output reg[4:0]area_length,output reg[6:0]body_length,
 output reg shown_remote,output reg[15:0]shown_id,shown_generation,output reg[1:0]shown_level
);
reg cached_valid;
reg[15:0]cached_id;
reg[15:0]cached_generation;
reg[1:0]cached_level;
wire wants_packet=requested_remote&&packet_valid;
wire target_ready=(requested_level>=2)?major_ready:(current_level<2||restore_ready);
assign install=frame_start&&pending&&(!frame_remote ||
 (target_ready&&(!wants_packet||pending_level==requested_level)));
assign advance_allowed=target_ready&&(!wants_packet ||
 (pending&&install&&pending_level==requested_level) ||
 (!pending&&cached_valid&&cached_level==requested_level));
always @(posedge clk or posedge rst)begin
 if(rst)begin
  cached_valid<=0;cached_id<=0;cached_level<=0;read_bank<=0;area_length<=0;body_length<=0;
  frame_remote<=0;shown_remote<=0;shown_id<=0;shown_level<=0;
  cached_generation<=0;shown_generation<=0;
 end else begin
  if(install)begin
   cached_valid<=1;cached_id<=pending_id;cached_level<=pending_level;
   cached_generation<=pending_generation;
   read_bank<=pending_bank;area_length<=pending_area;body_length<=pending_body;
  end
  if(frame_start&&advance_allowed)frame_remote<=wants_packet;
  if(first_pixel)begin shown_remote<=frame_remote;shown_id<=cached_id;shown_level<=current_level;shown_generation<=cached_generation;end
 end
end
endmodule
