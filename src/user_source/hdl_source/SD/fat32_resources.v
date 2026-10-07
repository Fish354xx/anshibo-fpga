// 只读FAT32资源索引与文件逻辑扇区映射。目录采用8.3短文件名。
// NORMAL/000..999.BMP按编号排序；ALERT/EVAC.BMP独立于日常列表。
// 可选PLAYLIST.TXT限512字节、16条，编号文件名加1..60秒停留时间。
// 控制寄存器使用同步复位；顶层rst_sd保持至少两个本域时钟。
// SPI驱动和跨时钟FIFO仍由原有异步复位链立即停止。
module fat32_resources #(
 parameter integer CLK_FREQ_HZ=100000000,
 parameter integer DEFAULT_SECONDS=5,
 parameter integer MAX_DIR_SECTORS=8192
)(
 input clk,rst,sd_init_done,
 output reg catalog_ready,
 output reg[4:0] normal_count,active_count,
 output reg emergency_file,
 output reg[7:0] status_flags,
 input select_file,input[4:0] file_index,input decoder_failed,
 output reg[5:0] selected_seconds,
 output reg load_error,
    output reg selected_fallback,
 input virtual_read,input[31:0] virtual_sector,
 output[7:0] virtual_data,output virtual_valid,output reg virtual_end,
 output reg physical_read,output reg[31:0] physical_sector,
 input[7:0] physical_data,input physical_valid,physical_end
);
localparam INIT=0,WAIT_PACKET=1,GAP=2,BOOT_BEGIN=3,BOOT_FETCH=4,BOOT_BYTE=5,
 BOOT_CHECK=6,GEOMETRY1=7,GEOMETRY2=8,GEOMETRY3=9,GEOMETRY4=10,
 DIR_START=11,DIR_REQ=12,DIR_BEGIN=13,DIR_FETCH=14,DIR_BYTE=15,ENTRY_CHECK=16,
 ENTRY_NEXT=17,DIR_LINK=18,DIR_FINISH=19,HEADER_BEGIN=20,HEADER_FETCH=21,
 HEADER_BYTE=22,HEADER_CALC1=23,HEADER_CALC2=24,HEADER_CHECK=25,
 INSERT_FIND=26,INSERT_SHIFT=27,INSERT_WRITE=28,
 FAT_BEGIN=29,FAT_FETCH=30,FAT_BYTE=31,FAT_DONE=32,
 CFG_START=33,CFG_FETCH=34,CFG_BYTE=35,CFG_CHECK=36,CFG_FIND=37,CFG_NEXT=38,
 FINALIZE=39,IDLE=40,SELECT1=41,SELECT2=42,SELECT3=43,
 V_MAP=44,V_NEXT=45,V_LINK=46,V_READ=47,V_DONE=48,V_HOLD=49,V_SYNTH=50,
 LBA1=51,LBA2=52,LBA3=53,CFG_PARSE1=54,CFG_PARSE2=55,HEADER_CALC3=56,FAT_ADDR=57,HEADER_CHECK_WAIT=58,GEOMETRY_WAIT=59,V_MAP_WAIT=60,INSERT_FIND_WAIT=61,CFG_FIND_WAIT=62;
reg[5:0] state,return_state,fat_return,cluster_return;
reg[27:0] wait_count;
localparam integer TIMEOUT_CYCLES=CLK_FREQ_HZ/2;
reg[8:0] receive_pos,parse_pos;
reg[9:0] received_count;
reg[7:0] sector_mem[0:511],sector_byte;
always @(posedge clk)begin
 if((state==WAIT_PACKET)&&physical_valid)sector_mem[receive_pos]<=physical_data;
 sector_byte<=sector_mem[parse_pos];
end
reg[31:0] volume_lba,volume_total,fat_lba,data_lba,cluster_count,cluster_last;
reg[32:0] volume_end,metadata_size,geometry_end;
reg[7:0] bpb_spc,bpb_fats,boot_first;
reg[15:0] bpb_bytes,bpb_reserved,bpb_roots,bpb_fat16,bpb_flags,bpb_version,signature;
reg[31:0] bpb_total,bpb_fat32,bpb_root;
reg[3:0] mbr_type[0:3];
reg[31:0] mbr_start[0:3],mbr_length[0:3];
reg[3:0] mbr_ok;
reg partitioned;
reg[31:0] partition_length;
reg[2:0] spc_shift;
reg[31:0] normal_dir,alert_dir,config_cluster,config_size,emergency_cluster,emergency_size;
reg[31:0] directory_cluster,directory_first;
reg[7:0] directory_sector;
reg[8:0] entry_offset;
reg[15:0] directory_walk;
reg[1:0] directory_kind;
reg directory_reload;
reg[87:0] entry_name;
reg[7:0] entry_attr;
reg[31:0] entry_cluster,entry_size;
reg[9:0] candidate_number;
reg[31:0] candidate_cluster,candidate_size;
reg candidate_emergency;
reg[15:0] bmp_signature,bmp_planes,bmp_bits;
reg[31:0] bmp_length,bmp_offset,bmp_dib,bmp_width,bmp_height,bmp_compression;
reg[12:0] bmp_stride;
reg[22:0] bmp_bytes;
reg[32:0] bmp_end;
reg bad_bmp,bad_geometry,decoder_failure_active;
reg[9:0] numbers[0:15];
reg[31:0] clusters[0:15],sizes[0:15];
reg[15:0] disabled;
reg[4:0] table_pos,insert_pos;
reg[3:0] playlist_index[0:15];
reg[5:0] playlist_seconds[0:15];
reg[4:0] playlist_count;
reg playlist_enabled;
reg[9:0] cfg_position;
reg[95:0] cfg_line;
reg[3:0] cfg_length;
reg cfg_bad,cfg_comment,cfg_eof;
reg cfg_bom;
reg[9:0] cfg_number;
reg[5:0] cfg_seconds;
wire[55:0] cfg_name=(cfg_length==7)?cfg_line[55:0]:
 (cfg_length==9)?cfg_line[71:16]:cfg_line[79:24];
wire cfg_name_ok=cfg_name[31:0]==".BMP"&&
 cfg_name[55:48]>="0"&&cfg_name[55:48]<="9"&&
 cfg_name[47:40]>="0"&&cfg_name[47:40]<="9"&&
 cfg_name[39:32]>="0"&&cfg_name[39:32]<="9";
reg[9:0] parsed_number,cfg_hundreds,cfg_tens,entry_number,entry_hundreds,entry_tens;
reg[7:0] parsed_seconds;
always @(posedge clk)begin
 cfg_hundreds<=cfg_name[51:48]*10'd100;cfg_tens<=cfg_name[43:40]*10'd10;
 parsed_number<=cfg_hundreds+cfg_tens+cfg_name[35:32];
 parsed_seconds<=(cfg_length==7)?DEFAULT_SECONDS:(cfg_length==9)?{4'd0,cfg_line[3:0]}:
  ({4'd0,cfg_line[11:8]}*8'd10)+{4'd0,cfg_line[3:0]};
 entry_hundreds<=entry_name[83:80]*10'd100;entry_tens<=entry_name[75:72]*10'd10;
 entry_number<=entry_hundreds+entry_tens+entry_name[67:64];
end
wire cfg_time_ok=(cfg_length==7)||
 (cfg_length==9&&cfg_line[15:8]==","&&cfg_line[7:0]>="1"&&cfg_line[7:0]<="9")||
 (cfg_length==10&&cfg_line[23:16]==","&&cfg_line[15:8]>="0"&&cfg_line[15:8]<="6"&&
 cfg_line[7:0]>="0"&&cfg_line[7:0]<="9"&&parsed_seconds>=1&&parsed_seconds<=60);
reg[31:0] lookup_cluster,fat_value;
reg[8:0] fat_offset;
reg[1:0] fat_byte_index;
reg[31:0] lba_cluster,lba_offset,lba_first;
reg[7:0] lba_sector_offset;
reg[31:0] file_cluster,file_size,map_cluster,pending_logical;
reg[14:0]map_logical,map_next_logical,file_sector_count;
reg map_same,map_next;
reg[9:0]table_number;
always @(posedge clk)begin
 map_next_logical<=map_logical+1'b1;
 map_same<=pending_logical==map_logical;map_next<=pending_logical==map_next_logical;
 table_number<=numbers[table_pos[3:0]];
end
reg[7:0] map_sector;
reg[4:0] selected_index,selected_slot;
reg[8:0] synthetic_pos;
reg synthetic_error;
wire[7:0] upper_byte=(sector_byte>="a"&&sector_byte<="z")?sector_byte-32:sector_byte;
wire data_cluster_ok=(fat_value[27:0]>=2)&&(fat_value[27:0]<=cluster_last)&&fat_value[27:0]<28'hFFFFFF0;
function cluster_ok;input[31:0] c;begin cluster_ok=c>=2&&c<=cluster_last&&c<32'h0FFFFFF0;end endfunction
function[7:0] fallback_byte;input[8:0] n;begin
 case(n)
 0:fallback_byte="B";1:fallback_byte="M";2:fallback_byte=58;
 10:fallback_byte=54;14:fallback_byte=40;18:fallback_byte=1;22:fallback_byte=1;
 26:fallback_byte=1;28:fallback_byte=24;34:fallback_byte=4;
 54:fallback_byte=8'h38;55:fallback_byte=8'h28;56:fallback_byte=8'h18;
 default:fallback_byte=0;
 endcase
end endfunction
assign virtual_data=((state==V_SYNTH))?(synthetic_error?8'd0:fallback_byte(synthetic_pos)):physical_data;
assign virtual_valid=((state==V_SYNTH))||((state==WAIT_PACKET)&&(return_state==V_DONE)&&physical_valid);
task packet;input[31:0] address;input[5:0] destination;begin
 physical_sector<=address;physical_read<=1;receive_pos<=0;received_count<=0;wait_count<=0;
 return_state<=destination;state<=WAIT_PACKET;
end endtask
task cluster_packet;input[31:0] c;input[7:0] offset;input[5:0] destination;begin
 lba_cluster<=c;lba_sector_offset<=offset;cluster_return<=destination;state<=LBA1;
end endtask
task fat_packet;input[31:0] c;input[5:0] destination;begin
 lookup_cluster<=c;fat_offset<={c[6:0],2'b00};fat_return<=destination;
 state<=FAT_ADDR;
end endtask
task directory_entry;begin
 parse_pos<=entry_offset;entry_name<=0;entry_attr<=0;entry_cluster<=0;entry_size<=0;
 state<=DIR_FETCH;
end endtask
task file_failure;begin
 load_error<=1;status_flags[6]<=1;synthetic_error<=1;synthetic_pos<=0;state<=V_SYNTH;
 if(selected_index<16)disabled[selected_slot]<=1;
 else emergency_file<=0;
end endtask
always @(posedge clk)begin
 if(rst)begin bad_bmp<=1;bad_geometry<=1;decoder_failure_active<=0;end
 else begin
  bad_bmp<=bmp_signature!=16'h4D42||bmp_planes!=1||bmp_bits!=24||bmp_compression!=0||bmp_dib<40||
   bmp_width==0||bmp_width>1280||bmp_height==0||bmp_height>960||bmp_offset<54||bmp_offset>4096||
   bmp_end>bmp_length||bmp_length>candidate_size;
  bad_geometry<=metadata_size[32]||metadata_size>=bpb_total||geometry_end[32]||
   (partitioned&&(volume_lba==0||bpb_total>partition_length))||cluster_count<65525||
   cluster_count>=32'h0FFFFFF0||({7'd0,bpb_fat32}<<7)<cluster_count+2||!cluster_ok(bpb_root);
  decoder_failure_active<=decoder_failed&&!select_file&&state!=SELECT1&&state!=SELECT2&&state!=SELECT3;
 end
end
integer i;
always @(posedge clk)begin
 if(rst)begin
  state<=INIT;return_state<=0;physical_read<=0;physical_sector<=0;receive_pos<=0;received_count<=0;parse_pos<=0;wait_count<=0;
  catalog_ready<=0;normal_count<=0;active_count<=0;emergency_file<=0;status_flags<=0;
  selected_seconds<=DEFAULT_SECONDS;load_error<=0;virtual_end<=0;selected_fallback<=1;
  volume_lba<=0;volume_total<=0;volume_end<=0;fat_lba<=0;data_lba<=0;cluster_count<=0;cluster_last<=0;
  bpb_spc<=0;bpb_fats<=0;bpb_bytes<=0;bpb_reserved<=0;bpb_roots<=0;bpb_fat16<=0;
  bpb_flags<=0;bpb_version<=0;bpb_total<=0;bpb_fat32<=0;bpb_root<=0;signature<=0;boot_first<=0;
  partitioned<=0;partition_length<=0;mbr_ok<=0;spc_shift<=0;metadata_size<=0;geometry_end<=0;
  normal_dir<=0;alert_dir<=0;config_cluster<=0;config_size<=0;emergency_cluster<=0;emergency_size<=0;
  directory_cluster<=0;directory_first<=0;directory_sector<=0;entry_offset<=0;directory_walk<=0;
  directory_kind<=0;directory_reload<=0;entry_name<=0;entry_attr<=0;entry_cluster<=0;entry_size<=0;
  candidate_number<=0;candidate_cluster<=0;candidate_size<=0;candidate_emergency<=0;
  bmp_signature<=0;bmp_planes<=0;bmp_bits<=0;bmp_length<=0;bmp_offset<=0;bmp_dib<=0;
  bmp_width<=0;bmp_height<=0;bmp_compression<=0;bmp_stride<=0;bmp_bytes<=0;bmp_end<=0;
  disabled<=0;table_pos<=0;insert_pos<=0;playlist_count<=0;playlist_enabled<=0;
  cfg_position<=0;cfg_line<=0;cfg_length<=0;cfg_bad<=0;cfg_comment<=0;cfg_eof<=0;cfg_number<=0;cfg_seconds<=0;cfg_bom<=0;
  lookup_cluster<=0;fat_value<=0;fat_offset<=0;fat_byte_index<=0;fat_return<=0;
  lba_cluster<=0;lba_offset<=0;lba_first<=0;lba_sector_offset<=0;cluster_return<=0;
  file_cluster<=0;file_size<=0;map_cluster<=0;map_sector<=0;map_logical<=0;pending_logical<=0;
  selected_index<=0;selected_slot<=0;synthetic_pos<=0;synthetic_error<=0;
  for(i=0;i<4;i=i+1)begin mbr_type[i]<=0;mbr_start[i]<=0;mbr_length[i]<=0;end
 end else begin
  virtual_end<=0;
  // Invalid runtime headers must not trap startup in endless retries.
  // Ignore old decoder feedback while installing the next descriptor.
  if(decoder_failure_active)begin
   status_flags[7]<=1;
   if(selected_index<16)disabled[selected_slot[3:0]]<=1;else emergency_file<=0;
  end
  case(state)
  INIT:begin
   if(sd_init_done)packet(0,BOOT_BEGIN);
   else if(wait_count>=CLK_FREQ_HZ*2-1)begin status_flags[0]<=1;state<=FINALIZE;end
   else wait_count<=wait_count+1'b1;
  end
  WAIT_PACKET:begin
   if(physical_valid)begin receive_pos<=receive_pos+1'b1;received_count<=received_count+1'b1;end
   if(physical_end)begin
    physical_read<=0;
    if((received_count==512&&!physical_valid)||(received_count==511&&physical_valid))state<=GAP;
    else begin
     status_flags[0]<=1;
     if(return_state==V_DONE)file_failure();else state<=FINALIZE;
    end
   end
   else if(wait_count>=TIMEOUT_CYCLES-1)begin
    physical_read<=0;status_flags[0]<=1;
    if((return_state==V_DONE))file_failure();else state<=FINALIZE;
   end else wait_count<=wait_count+1'b1;
  end
  GAP:state<=return_state;
  BOOT_BEGIN:begin parse_pos<=0;signature<=0;mbr_ok<=0;state<=BOOT_FETCH;end
  BOOT_FETCH:state<=BOOT_BYTE;
  BOOT_BYTE:begin
   case(parse_pos)
    0:boot_first<=sector_byte;
    11:bpb_bytes[7:0]<=sector_byte;12:bpb_bytes[15:8]<=sector_byte;
    13:bpb_spc<=sector_byte;14:bpb_reserved[7:0]<=sector_byte;15:bpb_reserved[15:8]<=sector_byte;
    16:bpb_fats<=sector_byte;17:bpb_roots[7:0]<=sector_byte;18:bpb_roots[15:8]<=sector_byte;
    22:bpb_fat16[7:0]<=sector_byte;23:bpb_fat16[15:8]<=sector_byte;
    32:bpb_total[7:0]<=sector_byte;33:bpb_total[15:8]<=sector_byte;
    34:bpb_total[23:16]<=sector_byte;35:bpb_total[31:24]<=sector_byte;
    36:bpb_fat32[7:0]<=sector_byte;37:bpb_fat32[15:8]<=sector_byte;
    38:bpb_fat32[23:16]<=sector_byte;39:bpb_fat32[31:24]<=sector_byte;
    40:bpb_flags[7:0]<=sector_byte;41:bpb_flags[15:8]<=sector_byte;
    42:bpb_version[7:0]<=sector_byte;43:bpb_version[15:8]<=sector_byte;
    44:bpb_root[7:0]<=sector_byte;45:bpb_root[15:8]<=sector_byte;
    46:bpb_root[23:16]<=sector_byte;47:bpb_root[31:24]<=sector_byte;
    450,466,482,498:begin mbr_ok[(parse_pos-450)>>4]<=sector_byte==8'h0B||sector_byte==8'h0C;end
    454,470,486,502:mbr_start[(parse_pos-454)>>4][7:0]<=sector_byte;
    455,471,487,503:mbr_start[(parse_pos-455)>>4][15:8]<=sector_byte;
    456,472,488,504:mbr_start[(parse_pos-456)>>4][23:16]<=sector_byte;
    457,473,489,505:mbr_start[(parse_pos-457)>>4][31:24]<=sector_byte;
    458,474,490,506:mbr_length[(parse_pos-458)>>4][7:0]<=sector_byte;
    459,475,491,507:mbr_length[(parse_pos-459)>>4][15:8]<=sector_byte;
    460,476,492,508:mbr_length[(parse_pos-460)>>4][23:16]<=sector_byte;
    461,477,493,509:mbr_length[(parse_pos-461)>>4][31:24]<=sector_byte;
    510:signature[7:0]<=sector_byte;511:signature[15:8]<=sector_byte;
   endcase
   if(parse_pos==511)state<=BOOT_CHECK;else begin parse_pos<=parse_pos+1'b1;state<=BOOT_FETCH;end
  end
  BOOT_CHECK:begin
   if(signature==16'hAA55&&(boot_first==8'hEB||boot_first==8'hE9)&&bpb_bytes==512&&
      bpb_spc!=0&&bpb_spc<=128&&(bpb_spc&(bpb_spc-1'b1))==0&&bpb_reserved!=0&&
      (bpb_fats==1||bpb_fats==2)&&bpb_roots==0&&bpb_fat16==0&&bpb_fat32!=0&&bpb_version==0&&
      (!bpb_flags[7]||bpb_flags[3:0]<bpb_fats))begin
    case(bpb_spc)1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;
     16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;endcase
    state<=GEOMETRY1;
   end else if(!partitioned&&signature==16'hAA55&&mbr_ok!=0)begin
    partitioned<=1;
    if(mbr_ok[0])begin volume_lba<=mbr_start[0];partition_length<=mbr_length[0];packet(mbr_start[0],BOOT_BEGIN);end
    else if(mbr_ok[1])begin volume_lba<=mbr_start[1];partition_length<=mbr_length[1];packet(mbr_start[1],BOOT_BEGIN);end
    else if(mbr_ok[2])begin volume_lba<=mbr_start[2];partition_length<=mbr_length[2];packet(mbr_start[2],BOOT_BEGIN);end
    else begin volume_lba<=mbr_start[3];partition_length<=mbr_length[3];packet(mbr_start[3],BOOT_BEGIN);end
   end else begin status_flags[0]<=1;state<=FINALIZE;end
  end
  GEOMETRY1:begin
   metadata_size<={17'd0,bpb_reserved}+(bpb_fats==2?{bpb_fat32,1'b0}:{1'b0,bpb_fat32});
   geometry_end<={1'b0,volume_lba}+{1'b0,bpb_total};state<=GEOMETRY2;
  end
  GEOMETRY2:begin
   data_lba<=volume_lba+metadata_size[31:0];
   fat_lba<=volume_lba+bpb_reserved+((bpb_flags[7]&&bpb_flags[0])?bpb_fat32:0);
   cluster_count<=(bpb_total-metadata_size[31:0])>>spc_shift;
   volume_end<=geometry_end;volume_total<=bpb_total;state<=GEOMETRY3;
  end
  GEOMETRY3:begin cluster_last<=cluster_count+1;state<=GEOMETRY_WAIT;end
  GEOMETRY_WAIT:state<=GEOMETRY4;
  GEOMETRY4:begin
   if(bad_geometry)begin
    status_flags[0]<=1;state<=FINALIZE;
   end else begin directory_kind<=0;directory_first<=bpb_root;directory_cluster<=bpb_root;state<=DIR_START;end
  end
  LBA1:begin lba_offset<=(lba_cluster-2)<<spc_shift;state<=LBA2;end
  LBA2:begin lba_first<=data_lba+lba_offset;state<=LBA3;end
  LBA3:packet(lba_first+lba_sector_offset,cluster_return);
  DIR_START:begin directory_sector<=0;entry_offset<=0;directory_walk<=0;directory_reload<=0;state<=DIR_REQ;end
  DIR_REQ:begin
   if(directory_walk>=MAX_DIR_SECTORS)begin status_flags[4]<=1;state<=DIR_FINISH;end
   else begin directory_walk<=directory_walk+1'b1;cluster_packet(directory_cluster,directory_sector,DIR_BEGIN);end
  end
  DIR_BEGIN:directory_entry();
  DIR_FETCH:state<=DIR_BYTE;
  DIR_BYTE:begin
   case(parse_pos[4:0])
    0,1,2,3,4,5,6,7,8,9,10:entry_name<={entry_name[79:0],upper_byte};
    11:entry_attr<=sector_byte;
    20:entry_cluster[23:16]<=sector_byte;21:entry_cluster[31:24]<=sector_byte;
    26:entry_cluster[7:0]<=sector_byte;27:entry_cluster[15:8]<=sector_byte;
    28:entry_size[7:0]<=sector_byte;29:entry_size[15:8]<=sector_byte;
    30:entry_size[23:16]<=sector_byte;31:entry_size[31:24]<=sector_byte;
   endcase
   if(parse_pos[4:0]==31)state<=ENTRY_CHECK;
   else begin parse_pos<=parse_pos+1'b1;state<=DIR_FETCH;end
  end
  ENTRY_CHECK:begin
   state<=ENTRY_NEXT;
   if(entry_name[87:80]==0)state<=DIR_FINISH;
   else if(entry_name[87:80]!=8'hE5&&entry_attr!=8'h0F&&!entry_attr[3])begin
    if(directory_kind==0)begin
     if(entry_attr[4]&&cluster_ok(entry_cluster))begin
      if(entry_name=="NORMAL     ")normal_dir<=entry_cluster;
      if(entry_name=="ALERT      ")alert_dir<=entry_cluster;
     end else if(!entry_attr[4]&&entry_name=="PLAYLISTTXT")begin
      if(entry_size>512||(!cluster_ok(entry_cluster)&&entry_size!=0))status_flags[5]<=1;
      else begin config_cluster<=entry_cluster;config_size<=entry_size;end
     end
    end else if(!entry_attr[4]&&cluster_ok(entry_cluster)&&entry_size>=54&&entry_size<=8388608)begin
     if((directory_kind==1&&entry_name[63:24]=="     "&&entry_name[23:0]=="BMP"&&
       entry_name[87:80]>="0"&&entry_name[87:80]<="9"&&entry_name[79:72]>="0"&&entry_name[79:72]<="9"&&
       entry_name[71:64]>="0"&&entry_name[71:64]<="9")||
       (directory_kind==2&&entry_name=="EVAC    BMP"))begin
      if(directory_kind==1&&normal_count>=16)status_flags[4]<=1;
      if(directory_kind==2||normal_count<16||entry_number<numbers[15])begin
       candidate_number<=entry_number;
       candidate_cluster<=entry_cluster;candidate_size<=entry_size;candidate_emergency<=directory_kind==2;
       directory_reload<=1;cluster_packet(entry_cluster,0,HEADER_BEGIN);
      end
     end
    end
   end
  end
  ENTRY_NEXT:begin
   if(entry_offset==480)begin
    entry_offset<=0;directory_reload<=0;
    if(directory_sector+1<bpb_spc)begin directory_sector<=directory_sector+1'b1;state<=DIR_REQ;end
    else fat_packet(directory_cluster,DIR_LINK);
   end else begin
    entry_offset<=entry_offset+32;
    if(directory_reload)begin directory_reload<=0;state<=DIR_REQ;end
    else begin parse_pos<=entry_offset+32;entry_name<=0;entry_attr<=0;entry_cluster<=0;entry_size<=0;state<=DIR_FETCH;end
   end
  end
  DIR_LINK:begin
   if(fat_value[27:0]>=28'hFFFFFF8)state<=DIR_FINISH;
   else if(!data_cluster_ok||fat_value[27:0]==directory_cluster||fat_value[27:0]==directory_first)begin
    status_flags[6]<=1;state<=DIR_FINISH;
   end else begin directory_cluster<={4'd0,fat_value[27:0]};directory_sector<=0;state<=DIR_REQ;end
  end
  DIR_FINISH:begin
   if(directory_kind==0)begin
    directory_kind<=1;
    if(normal_dir!=0)begin directory_first<=normal_dir;directory_cluster<=normal_dir;state<=DIR_START;end
   end else if(directory_kind==1)begin
    directory_kind<=2;
    if(alert_dir!=0)begin directory_first<=alert_dir;directory_cluster<=alert_dir;state<=DIR_START;end
   end else if(config_size!=0)cluster_packet(config_cluster,0,CFG_START);
   else state<=FINALIZE;
  end
  HEADER_BEGIN:begin
   parse_pos<=0;bmp_signature<=0;bmp_planes<=0;bmp_bits<=0;bmp_length<=0;bmp_offset<=0;
   bmp_dib<=0;bmp_width<=0;bmp_height<=0;bmp_compression<=0;state<=HEADER_FETCH;
  end
  HEADER_FETCH:state<=HEADER_BYTE;
  HEADER_BYTE:begin
   case(parse_pos)
    0:bmp_signature[7:0]<=sector_byte;1:bmp_signature[15:8]<=sector_byte;
    2:bmp_length[7:0]<=sector_byte;3:bmp_length[15:8]<=sector_byte;4:bmp_length[23:16]<=sector_byte;5:bmp_length[31:24]<=sector_byte;
    10:bmp_offset[7:0]<=sector_byte;11:bmp_offset[15:8]<=sector_byte;12:bmp_offset[23:16]<=sector_byte;13:bmp_offset[31:24]<=sector_byte;
    14:bmp_dib[7:0]<=sector_byte;15:bmp_dib[15:8]<=sector_byte;16:bmp_dib[23:16]<=sector_byte;17:bmp_dib[31:24]<=sector_byte;
    18:bmp_width[7:0]<=sector_byte;19:bmp_width[15:8]<=sector_byte;20:bmp_width[23:16]<=sector_byte;21:bmp_width[31:24]<=sector_byte;
    22:bmp_height[7:0]<=sector_byte;23:bmp_height[15:8]<=sector_byte;24:bmp_height[23:16]<=sector_byte;25:bmp_height[31:24]<=sector_byte;
    26:bmp_planes[7:0]<=sector_byte;27:bmp_planes[15:8]<=sector_byte;28:bmp_bits[7:0]<=sector_byte;29:bmp_bits[15:8]<=sector_byte;
    30:bmp_compression[7:0]<=sector_byte;31:bmp_compression[15:8]<=sector_byte;32:bmp_compression[23:16]<=sector_byte;33:bmp_compression[31:24]<=sector_byte;
   endcase
   if(parse_pos==53)state<=HEADER_CALC1;else begin parse_pos<=parse_pos+1'b1;state<=HEADER_FETCH;end
  end
  HEADER_CALC1:begin bmp_stride<=({2'd0,bmp_width[10:0]}*13'd3+13'd3)&13'h1FFC;state<=HEADER_CALC2;end
  HEADER_CALC2:begin bmp_bytes<=bmp_stride*bmp_height[9:0];state<=HEADER_CALC3;end
  HEADER_CALC3:begin bmp_end<={1'b0,bmp_offset}+bmp_bytes;state<=HEADER_CHECK_WAIT;end
  HEADER_CHECK_WAIT:state<=HEADER_CHECK;
  HEADER_CHECK:begin
   if(bad_bmp)begin
    status_flags[3]<=1;state<=ENTRY_NEXT;
   end else if(candidate_emergency)begin emergency_file<=1;emergency_cluster<=candidate_cluster;emergency_size<=candidate_size;state<=ENTRY_NEXT;end
   else begin table_pos<=0;state<=INSERT_FIND_WAIT;end
  end
  INSERT_FIND:begin
   if(table_pos==normal_count||candidate_number<table_number)begin
    insert_pos<=table_pos;table_pos<=normal_count==16?15:normal_count;state<=INSERT_SHIFT;
   end else begin table_pos<=table_pos+1'b1;state<=INSERT_FIND_WAIT;end
  end
  INSERT_SHIFT:begin
   if(table_pos==insert_pos)state<=INSERT_WRITE;
   else begin
    numbers[table_pos[3:0]]<=numbers[table_pos-1'b1];clusters[table_pos[3:0]]<=clusters[table_pos-1'b1];sizes[table_pos[3:0]]<=sizes[table_pos-1'b1];
    table_pos<=table_pos-1'b1;
   end
  end
  INSERT_WRITE:begin
   numbers[insert_pos[3:0]]<=candidate_number;clusters[insert_pos[3:0]]<=candidate_cluster;sizes[insert_pos[3:0]]<=candidate_size;
   if(normal_count<16)normal_count<=normal_count+1'b1;state<=ENTRY_NEXT;
  end
  FAT_ADDR:packet(fat_lba+(lookup_cluster>>7),FAT_BEGIN);
  FAT_BEGIN:begin parse_pos<=fat_offset;fat_value<=0;fat_byte_index<=0;state<=FAT_FETCH;end
  FAT_FETCH:state<=FAT_BYTE;
  FAT_BYTE:begin
   case(fat_byte_index)0:fat_value[7:0]<=sector_byte;1:fat_value[15:8]<=sector_byte;
    2:fat_value[23:16]<=sector_byte;3:fat_value[31:24]<=sector_byte;endcase
   if(fat_byte_index==3)state<=FAT_DONE;
   else begin fat_byte_index<=fat_byte_index+1'b1;parse_pos<=parse_pos+1'b1;state<=FAT_FETCH;end
  end
  FAT_DONE:state<=fat_return;
  CFG_START:begin cfg_position<=0;cfg_line<=0;cfg_length<=0;cfg_bad<=0;cfg_comment<=0;cfg_eof<=0;cfg_bom<=0;parse_pos<=0;state<=CFG_FETCH;end
  CFG_FETCH:begin
   if(cfg_position>=config_size)begin cfg_eof<=1;state<=CFG_PARSE1;end
   else state<=CFG_BYTE;
  end
  CFG_BYTE:begin
   cfg_position<=cfg_position+1'b1;parse_pos<=parse_pos+1'b1;
   if(cfg_position==0&&sector_byte==8'hEF)begin cfg_bom<=1;state<=CFG_FETCH;end
   else if(cfg_bom&&cfg_position<3)begin
    if((cfg_position==1&&sector_byte!=8'hBB)||(cfg_position==2&&sector_byte!=8'hBF))cfg_bad<=1;
    state<=CFG_FETCH;
   end else if(sector_byte==10||sector_byte==13)state<=CFG_PARSE1;
   else begin
    if(cfg_length==0&&sector_byte=="#")cfg_comment<=1;
    if(!cfg_comment)begin
     if(cfg_length>=12)cfg_bad<=1;
     else begin cfg_line<={cfg_line[87:0],upper_byte};cfg_length<=cfg_length+1'b1;end
    end
    state<=CFG_FETCH;
   end
  end
  CFG_PARSE1:state<=CFG_PARSE2;
  CFG_PARSE2:state<=CFG_CHECK;
  CFG_CHECK:begin
   if(cfg_comment||cfg_length==0)state<=CFG_NEXT;
   else if(cfg_bad||!cfg_name_ok||!cfg_time_ok)begin status_flags[5]<=1;state<=CFG_NEXT;end
   else begin cfg_number<=parsed_number;cfg_seconds<=parsed_seconds[5:0];table_pos<=0;state<=CFG_FIND_WAIT;end
  end
  CFG_FIND:begin
   if(table_pos>=normal_count)begin status_flags[5]<=1;state<=CFG_NEXT;end
   else if(table_number==cfg_number)begin
    if(playlist_count>=16)status_flags[4]<=1;
    else begin playlist_index[playlist_count[3:0]]<=table_pos[3:0];playlist_seconds[playlist_count[3:0]]<=cfg_seconds;playlist_count<=playlist_count+1'b1;end
    state<=CFG_NEXT;
   end else begin table_pos<=table_pos+1'b1;state<=CFG_FIND_WAIT;end
  end
  CFG_NEXT:begin
   cfg_line<=0;cfg_length<=0;cfg_bad<=0;cfg_comment<=0;
   if(cfg_eof)state<=FINALIZE;else state<=CFG_FETCH;
  end
  FINALIZE:begin
   catalog_ready<=1;playlist_enabled<=playlist_count!=0;active_count<=playlist_count!=0?playlist_count:normal_count;
   if(normal_count==0)status_flags[1]<=1;
   if(!emergency_file)status_flags[2]<=1;
   if(status_flags[0])begin normal_count<=0;active_count<=0;emergency_file<=0;playlist_enabled<=0;status_flags[2:1]<=2'b11;end
   state<=IDLE;
  end
  IDLE:begin
   if(select_file)begin selected_index<=file_index;load_error<=0;synthetic_error<=0;state<=SELECT1;end
   else if(virtual_read)begin pending_logical<=virtual_sector;state<=V_MAP_WAIT;end
  end
  SELECT1:begin selected_slot<=playlist_enabled?{1'b0,playlist_index[selected_index[3:0]]}:selected_index;state<=SELECT2;end
  SELECT2:begin
   selected_seconds<=(selected_index<16&&playlist_enabled)?playlist_seconds[selected_index[3:0]]:DEFAULT_SECONDS;
   if(selected_index==16)begin file_cluster<=emergency_file&&!status_flags[0]?emergency_cluster:0;file_size<=emergency_file?emergency_size:58;end
   else if(selected_index>=active_count||disabled[selected_slot[3:0]]||status_flags[0])begin file_cluster<=0;file_size<=58;end
   else begin file_cluster<=clusters[selected_slot[3:0]];file_size<=sizes[selected_slot[3:0]];end
   state<=SELECT3;
  end
  SELECT3:begin selected_fallback<=file_cluster==0;map_cluster<=file_cluster;map_sector<=0;map_logical<=0;file_sector_count<=(file_size+511)>>9;state<=IDLE;end
  V_MAP_WAIT:state<=V_MAP;
  INSERT_FIND_WAIT:state<=INSERT_FIND;
  CFG_FIND_WAIT:state<=CFG_FIND;
  V_MAP:begin
   if(file_cluster==0)begin synthetic_pos<=0;synthetic_error<=0;state<=V_SYNTH;end
   else if(load_error)begin synthetic_pos<=0;synthetic_error<=1;state<=V_SYNTH;end
   else if(pending_logical>=file_sector_count)file_failure();
   else if(pending_logical==0)begin map_cluster<=file_cluster;map_sector<=0;map_logical<=0;state<=V_READ;end
   else if(map_same)state<=V_READ;
   else if(map_next)state<=V_NEXT;
   else file_failure();
  end
  V_NEXT:begin
   if(map_sector+1<bpb_spc)begin map_sector<=map_sector+1'b1;map_logical<=pending_logical;state<=V_READ;end
   else fat_packet(map_cluster,V_LINK);
  end
  V_LINK:begin
   if(!data_cluster_ok||fat_value[27:0]==map_cluster||fat_value[27:0]==file_cluster)file_failure();
   else begin map_cluster<={4'd0,fat_value[27:0]};map_sector<=0;map_logical<=pending_logical;state<=V_READ;end
  end
  V_READ:cluster_packet(map_cluster,map_sector,V_DONE);
  V_DONE:begin virtual_end<=1;state<=V_HOLD;end
  V_SYNTH:begin
   if(synthetic_pos==511)begin virtual_end<=1;state<=V_HOLD;end
   else synthetic_pos<=synthetic_pos+1'b1;
  end
  V_HOLD:if(!virtual_read)state<=IDLE;
  default:state<=INIT;
  endcase
 end
end
endmodule
