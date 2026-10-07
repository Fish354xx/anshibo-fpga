// 文件：bmp_read.v
// 职责：校验并读取BMP，使用行缓存完成最近邻缩放和背压限速。
// 来源与修改说明：参见SOURCE_ORIGIN.md。
// 约束：正高度RGB24非压缩BMP，宽1～1280、高1～960，输出640×480。
// 协议：write_ready为写侧背压；帧提交需同时等待源读取和内存写入完成。
module bmp_read #(parameter integer EARLY_FIRST_IMAGE=0,parameter integer FILE_READ_ENABLE=0)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input                       scan_resume,
    output reg                  scan_paused,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    input                       file_read_error,
    output reg                  load_failed,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,
    input                       write_ready,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output                      bmp_data_wr_en,
    output [23:0]               bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
localparam ST_FETCH = 3'd5, ST_OFFER = 3'd6, ST_FINISH = 3'd7;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] dib_size;
reg [15:0] planes;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

reg header_match;
wire bmp_data_valid;
reg [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;

assign ready = (state == ST_IDLE);
// Header values finish at byte 33; this calculation pipeline settles long
// before the 512-byte header sector ends. Split the product into small DSPs.
reg [12:0] row_stride;
reg [17:0] bytes_lo,bytes_hi;
reg [22:0] image_bytes;
reg [31:0] pixel_end;
always @(posedge clk) begin
    row_stride<=({2'b0,width[10:0]}*13'd3+13'd3)&13'h1FFC;
    bytes_lo<=row_stride*height[4:0];
    bytes_hi<=row_stride*height[9:5];
    image_bytes<={5'd0,bytes_lo}+{bytes_hi,5'd0};
    pixel_end<=pixel_offset+{9'd0,image_bytes};
end
always @(posedge clk) begin
header_match <= (header_0=="B") && (header_1=="M") &&
    (width>0 && width<=1280) && (height>0 && height<=960) &&
    bit_count==24 && compression==0 && dib_size>=40 && planes==1 &&
    pixel_offset>=54 && pixel_offset<=4096 && pixel_end<=file_len && file_len<=8388608;
end
assign bmp_data_valid = (state==ST_OFFER) && (bmp_len_cnt>=pixel_offset) && (bmp_len_cnt<pixel_end);
reg [7:0] sector_mem[0:511];
reg [8:0] sector_wr,sector_pos;
reg [7:0] sector_byte;
reg scale_start;
wire scale_ready,scale_done;
bmp_nearest_scaler u_scaler(.clk(clk),.rst(rst),.start(scale_start),
    .src_width(width[10:0]),.src_height(height[9:0]),
    .in_valid(bmp_data_valid),.in_byte(sector_byte),.in_ready(scale_ready),
    .out_ready(write_ready),.out_valid(bmp_data_wr_en),.out_rgb(bmp_data),.done(scale_done));
always @(posedge clk) begin
    if(state==ST_LOAD_DATA && sd_sec_read_data_valid) sector_mem[sector_wr]<=sd_sec_read_data;
    if(state==ST_FETCH) sector_byte<=sector_mem[sector_pos];
end
always @(posedge clk)
    file_sector_count <= (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_match = scan_sector + file_sector_count;
// 仅在签名和几何信息有效时跳过MBR/FAT32元数据；否则沿用逐扇区扫描。
reg [15:0] boot_signature,bpb_bytes,bpb_reserved,bpb_roots,bpb_fat16,bpb_version;
reg [7:0] partition_type,bpb_spc,bpb_fats;
reg [31:0] partition_start,bpb_fat32,bpb_total,bpb_rootcluster;
// 元数据几何计算提前流水化，字段在扇区前48字节完成，后续有足够稳定时间。
reg [32:0] metadata_sectors,data_start;
reg fat32_geometry_valid;
always @(posedge clk) begin
    metadata_sectors<={17'd0,bpb_reserved}+
        (bpb_fats==2 ? {bpb_fat32,1'b0} : {1'b0,bpb_fat32});
    data_start<={1'b0,scan_sector}+metadata_sectors;
    fat32_geometry_valid<=bpb_bytes==512 && bpb_reserved!=0 &&
        (bpb_fats==1 || bpb_fats==2) && bpb_spc!=0 && ((bpb_spc & (bpb_spc-1'b1))==0) &&
        bpb_roots==0 && bpb_fat16==0 && bpb_version==0 && bpb_fat32!=0 && bpb_rootcluster>=2 &&
        metadata_sectors<{1'b0,bpb_total} && data_start<= {1'b0,scan_max_sector};
end
wire valid_mbr=(scan_sector==0 && scan_found_total==0 && boot_signature==16'hAA55 &&
    (partition_type==8'h0B || partition_type==8'h0C) && partition_start>0 && partition_start<=scan_max_sector);
wire valid_fat32=(scan_found_total==0 && boot_signature==16'hAA55 &&
    (header_0==8'hEB || header_0==8'hE9) && fat32_geometry_valid);
assign next_scan_sector_if_miss=valid_mbr?partition_start:valid_fat32?data_start[31:0]:scan_sector+32'd1;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        boot_signature<=0;partition_type<=0;partition_start<=0;
        bpb_bytes<=0;bpb_reserved<=0;bpb_roots<=0;bpb_fat16<=0;bpb_version<=0;
        bpb_spc<=0;bpb_fats<=0;bpb_fat32<=0;bpb_total<=0;bpb_rootcluster<=0;
    end else if(state==ST_SCAN && sd_sec_read_data_valid) begin
        case(rd_cnt)
            11:bpb_bytes[7:0]<=sd_sec_read_data;12:bpb_bytes[15:8]<=sd_sec_read_data;
            13:bpb_spc<=sd_sec_read_data;14:bpb_reserved[7:0]<=sd_sec_read_data;
            15:bpb_reserved[15:8]<=sd_sec_read_data;16:bpb_fats<=sd_sec_read_data;
            17:bpb_roots[7:0]<=sd_sec_read_data;18:bpb_roots[15:8]<=sd_sec_read_data;
            22:bpb_fat16[7:0]<=sd_sec_read_data;23:bpb_fat16[15:8]<=sd_sec_read_data;
            32:bpb_total[7:0]<=sd_sec_read_data;33:bpb_total[15:8]<=sd_sec_read_data;
            34:bpb_total[23:16]<=sd_sec_read_data;35:bpb_total[31:24]<=sd_sec_read_data;
            36:bpb_fat32[7:0]<=sd_sec_read_data;37:bpb_fat32[15:8]<=sd_sec_read_data;
            38:bpb_fat32[23:16]<=sd_sec_read_data;39:bpb_fat32[31:24]<=sd_sec_read_data;
            42:bpb_version[7:0]<=sd_sec_read_data;43:bpb_version[15:8]<=sd_sec_read_data;
            44:bpb_rootcluster[7:0]<=sd_sec_read_data;45:bpb_rootcluster[15:8]<=sd_sec_read_data;
            46:bpb_rootcluster[23:16]<=sd_sec_read_data;47:bpb_rootcluster[31:24]<=sd_sec_read_data;
            450:partition_type<=sd_sec_read_data;
            454:partition_start[7:0]<=sd_sec_read_data;455:partition_start[15:8]<=sd_sec_read_data;
            456:partition_start[23:16]<=sd_sec_read_data;457:partition_start[31:24]<=sd_sec_read_data;
            510:boot_signature[7:0]<=sd_sec_read_data;511:boot_signature[15:8]<=sd_sec_read_data;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0; dib_size<=0;planes<=0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            14: dib_size[7:0]<=sd_sec_read_data;
            15: dib_size[15:8]<=sd_sec_read_data;
            16: dib_size[23:16]<=sd_sec_read_data;
            17: dib_size[31:24]<=sd_sec_read_data;
            26: planes[7:0]<=sd_sec_read_data;
            27: planes[15:8]<=sd_sec_read_data;
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        load_failed<=0;
        bmp_len_cnt<=0;sector_wr<=0;sector_pos<=0;scale_start<=0;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_paused       <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        load_failed<=0;
        bmp_len_cnt<=0;sector_wr<=0;sector_pos<=0;scale_start<=0;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_paused       <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;
        scale_start<=0;

        if(FILE_READ_ENABLE&&file_read_error)load_failed<=1;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_paused      <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (scan_resume && scan_paused) begin
                    scan_paused<=0; sd_sec_read_addr<=scan_sector; state<=ST_SCAN;
                end else if (load_start) begin
                    load_failed<=0;
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else if(EARLY_FIRST_IMAGE && scan_found_total==0) begin
                            // 首图先加载显示；scan_sector保存续扫位置，计数不清零。
                            scan_paused<=1;state<=ST_IDLE;
                            sd_sec_read_addr<=next_scan_sector_if_match;
                            scan_sector<=next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        load_failed<=1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                    bmp_len_cnt<=0;sector_wr<=0;sector_pos<=0;scale_start<=1;
                end
            end

            ST_LOAD_DATA: begin
                state_code<=4'd4; sd_sec_read<=1;
                if(sd_sec_read_data_valid) sector_wr<=sector_wr+1'b1;
                if(sd_sec_read_end) begin
                    sd_sec_read<=0;sector_pos<=0;sector_wr<=0;state<=ST_FETCH;
                end
            end
            ST_FETCH: begin
                sd_sec_read<=0;state<=ST_OFFER;
            end
            ST_OFFER: begin
                if(!bmp_data_valid || scale_ready) begin
                    bmp_len_cnt<=bmp_len_cnt+1'b1;
                    if(bmp_len_cnt+1>=pixel_end) state<=ST_FINISH;
                    else if(sector_pos==511) begin
                        sd_sec_read_addr<=sd_sec_read_addr+1'b1;state<=ST_LOAD_DATA;
                    end else begin sector_pos<=sector_pos+1'b1;state<=ST_FETCH;end
                end
            end
            ST_FINISH: begin
                sd_sec_read<=0;
                if(scale_done) state<=ST_IDLE;
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule

// Streaming nearest-neighbour scaler. A single output-width line is stored;
// the sector feeder pauses while rows are repeated or FIFO output is blocked.
module bmp_nearest_scaler #(
    parameter OUT_WIDTH=640, OUT_HEIGHT=480,
    parameter OUTPUT_GAP=14
)(
    input clk,rst,start,
    input [10:0] src_width,
    input [9:0] src_height,
    input in_valid,
    input [7:0] in_byte,
    output in_ready,
    input out_ready,
    output reg out_valid,
    output reg [23:0] out_rgb,
    output done
);
localparam READ=0,MAP=1,HSTEP=2,PIXEND=3,PAD=4,ROWEND=5,
           EMIT_ADDR=6,EMIT_WRITE=7,VSTEP=8,NEXTROW=9,DONE=10,EMIT_WAIT=11;
reg [3:0] state;
reg [10:0] sx,want_x;
reg [9:0] sy,want_y,ox,oy;
reg [12:0] h_acc,v_acc;
reg [1:0] byte_idx,pad_left;
reg [23:0] pixel,line_pixel;
reg [4:0] output_gap;
reg [3:0] after_emit;
reg [23:0] line_mem[0:OUT_WIDTH-1];
// After the last output row, drain any remaining unselected source rows.
assign in_ready=(state==READ || state==PAD || state==DONE);
assign done=(state==DONE);
always @(posedge clk) begin
    if(state==MAP && sy==want_y && sx==want_x && ox<OUT_WIDTH)
        line_mem[ox]<=pixel;
    if(state==EMIT_ADDR) line_pixel<=line_mem[ox];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=DONE;out_valid<=0;out_rgb<=0;
        sx<=0;sy<=0;want_x<=0;want_y<=0;ox<=0;oy<=0;
        h_acc<=0;v_acc<=0;byte_idx<=0;pad_left<=0;pixel<=0;
        output_gap<=0;after_emit<=DONE;
    end else begin
        out_valid<=0;
        if(start) begin
            state<=READ;sx<=0;sy<=0;want_x<=0;want_y<=0;ox<=0;oy<=0;
            h_acc<=0;v_acc<=0;byte_idx<=0;pad_left<=0;pixel<=0;
        end else case(state)
        READ: if(in_valid) begin
            case(byte_idx)
            0: begin pixel[7:0]<=in_byte;byte_idx<=1;end
            1: begin pixel[15:8]<=in_byte;byte_idx<=2;end
            2: begin pixel[23:16]<=in_byte;byte_idx<=0;state<=MAP;end
            endcase
        end
        MAP: if(sy==want_y && sx==want_x && ox<OUT_WIDTH) begin
            ox<=ox+1'b1;h_acc<=h_acc+src_width;state<=HSTEP;
        end else state<=PIXEND;
        HSTEP: if(h_acc>=OUT_WIDTH) begin h_acc<=h_acc-OUT_WIDTH;want_x<=want_x+1'b1;end
               else state<=MAP;
        PIXEND: if(sx==src_width-1'b1) begin
            pad_left<=src_width[1:0];
            if(src_width[1:0]!=0) state<=PAD;else state<=ROWEND;
        end else begin sx<=sx+1'b1;state<=READ;end
        PAD: if(in_valid) begin
            if(pad_left==1) state<=ROWEND;
            pad_left<=pad_left-1'b1;
        end
        ROWEND: if(sy==want_y) begin ox<=0;state<=EMIT_ADDR;end
                else state<=NEXTROW;
        EMIT_ADDR: state<=EMIT_WRITE;
        EMIT_WRITE: if(out_ready) begin
            out_rgb<=line_pixel;out_valid<=1;
            // Shared SDRAM gives writes burst priority. Pace line replay so
            // repeated/scaled rows cannot monopolize read-FIFO refill time.
            output_gap<=OUTPUT_GAP-1;
            state<=EMIT_WAIT;
            if(ox==OUT_WIDTH-1) begin oy<=oy+1'b1;v_acc<=v_acc+src_height;after_emit<=VSTEP;end
            else begin ox<=ox+1'b1;after_emit<=EMIT_ADDR;end
        end
        EMIT_WAIT: if(output_gap==0) state<=after_emit;
                   else output_gap<=output_gap-1'b1;
        VSTEP: if(v_acc>=OUT_HEIGHT) begin v_acc<=v_acc-OUT_HEIGHT;want_y<=want_y+1'b1;end
               else if(oy==OUT_HEIGHT) state<=DONE;
               else if(want_y==sy) begin ox<=0;state<=EMIT_ADDR;end
               else state<=NEXTROW;
        NEXTROW: begin
            sy<=sy+1'b1;sx<=0;want_x<=0;ox<=0;h_acc<=0;byte_idx<=0;state<=READ;
        end
        default: state<=DONE;
        endcase
    end
end
endmodule
