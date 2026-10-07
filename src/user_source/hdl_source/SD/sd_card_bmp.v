// 文件：sd_card_bmp.v
// 职责：协调扫描加载、双缓存提交、按键调节、轮播及应急模式。
// 来源与修改说明：参见SOURCE_ORIGIN.md。
// 优先级：应急模式优先；普通模式支持手动切图、轮播和参数调节。
// 跨域：内存完成以toggle同步；转场握手在完整图片可用后提交缓存。

module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer REMOTE_ENABLE = 0,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer FRAME_READER_FEEDBACK = 0,
    parameter integer RESOURCE_ENABLE = 0
)(
    input                       clk,
    input                       rst,
    input                       adjustment_switch,
    input                       contrast_switch,
    input                       command_valid,
    input [3:0]                 command_code,
    input [4:0]                 command_value,
    output                      auto_play_active,
    output [4:0] resource_normal_count,resource_active_count,resource_index,
    output reg [5:0] resource_seconds,
    output [7:0] resource_flags,
    output resource_catalog_ready,resource_emergency_file,
    output reg display_fallback,
    input                       remote_next,       // 同时钟域串口切图脉冲
    output [2:0]                next_block_reason, // 串口操作拒绝原因
    input                       key_next,
    input                       key_auto,
    input                       key_mode,           // 模式切换按键（普通/应急），原始引脚

    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output                      o_emergency_loaded, // 应急图已完整提交到显示缓冲
    output                      o_emergency_mode,   // 0=普通模式 1=应急模式（面板指示）
    output [15:0]               debug_status,
    output [7:0]                picture_settings,
    output                      transition_pending,
    input                       transition_black_ready,
    input [1:0]                 read_active_index_async,
    input                       read_slide_mix_async,transition_cancel_ack_async,
    output reg                  transition_cancel_request,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    input                       write_ready,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

localparam integer INDEX_BITS=RESOURCE_ENABLE?5:2;
localparam [INDEX_BITS-1:0] EMERGENCY_SLOT=RESOURCE_ENABLE?16:3;
wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire bmp_scan_done;
wire scan_done=RESOURCE_ENABLE?resource_catalog_ready:bmp_scan_done;
wire             scan_paused;
wire scan_resume;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg [INDEX_BITS:0] img_found_count;
reg [INDEX_BITS-1:0] img_idx;              // 当前真正显示中的图片编号
reg [INDEX_BITS-1:0] load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              load_busy;
assign scan_resume=scan_paused && first_image_committed && bmp_ready && !load_busy;

// 普通模式/应急模式控制器接口
wire             ctrl_load_req;        // 加载请求（仅流水空闲时拉高，单周期）
wire [INDEX_BITS-1:0] ctrl_load_idx;        // 请求加载的图片编号
wire             ctrl_load_is_emerg;   // 该请求是否为应急图
wire ctrl_disp_commit_en;
wire bmp_load_failed,resource_load_error,resource_selected_fallback;
wire[5:0]resource_hold_seconds;
reg source_started_seen;
wire disp_commit_en=ctrl_disp_commit_en&&!(RESOURCE_ENABLE&&source_started_seen&&(bmp_load_failed||resource_load_error));
reg write_started,retry_emergency;
wire[4:0] effective_resource_count=(resource_active_count==0)?5'd1:resource_active_count;
assign resource_index=img_idx;

// bmp_ready 先表示"源文件读取/送 FIFO 完成"；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              memory_done_seen;
reg [1:0]        transition_ready_sync;
wire             commit_allowed;
reg [1:0] reader_index_sync0,reader_index_sync1;
reg reader_mix_sync0,reader_mix_sync1,cancel_ack_sync0,cancel_ack_sync1,cancel_started;
wire reader_bank_safe=!FRAME_READER_FEEDBACK || !display_valid ||
    (reader_index_sync1==disp_buf_idx && !reader_mix_sync1);
wire retire_safe=!FRAME_READER_FEEDBACK || disp_commit_en ||
    (cancel_started && cancel_ack_sync1==transition_cancel_request);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  reader_index_sync0<=0;reader_index_sync1<=0;reader_mix_sync0<=0;reader_mix_sync1<=0;
  cancel_ack_sync0<=0;cancel_ack_sync1<=0;transition_cancel_request<=0;cancel_started<=0;
 end else begin
  reader_index_sync0<=read_active_index_async;reader_index_sync1<=reader_index_sync0;
  reader_mix_sync0<=read_slide_mix_async;reader_mix_sync1<=reader_mix_sync0;
  cancel_ack_sync0<=transition_cancel_ack_async;cancel_ack_sync1<=cancel_ack_sync0;
  if(!load_busy)cancel_started<=0;
  else if(FRAME_READER_FEEDBACK&&!disp_commit_en&&!cancel_started)begin
   transition_cancel_request<=~transition_cancel_request;cancel_started<=1;
  end
 end
end
frame_commit_gate u_frame_commit_gate(
    .load_busy(load_busy && retire_safe), .source_done(source_done_seen), .memory_done(memory_done_seen),
    .display_valid(display_valid), .emergency_mode(o_emergency_mode || o_emergency_loaded),
    .display_permit(disp_commit_en), .black_ready(transition_ready_sync[1]),
    .transition_pending(transition_pending), .commit_allowed(commit_allowed));

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
reg [1:0]        write_ack_sync;
wire             write_finish_pulse;

assign o_emergency_loaded = display_valid && (img_idx==EMERGENCY_SLOT);
assign write_en           = bmp_data_wr_en;
assign write_data         = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
// Read-only diagnostics: image count / displayed index / loading index / status flags.
wire[3:0] debug_count=(img_found_count>15)?4'hF:img_found_count;
wire[3:0] debug_image=(img_idx>15)?4'hF:img_idx;
wire[3:0] debug_loading=(load_idx>15)?4'hF:load_idx;
assign debug_status={debug_count,debug_image,debug_loading,scan_done,bmp_ready,load_busy,o_emergency_mode};

wire settings_active;
assign next_block_reason = (!scan_done || !display_valid) ? 3'd1 :
                           o_emergency_mode ? 3'd2 : settings_active ? 3'd3 :
                           ((RESOURCE_ENABLE?effective_resource_count:img_found_count)<2) ? 3'd5 : load_busy ? 3'd4 : 3'd0;
picture_key_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_picture_keys (
    .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
    .adjustment_switch(adjustment_switch), .contrast_switch(contrast_switch),
    .remote_brightness_valid(REMOTE_ENABLE && command_valid && command_code==5),
    .remote_contrast_valid(REMOTE_ENABLE && command_valid && command_code==6),
    .remote_level(command_value[2:0]),
    .emergency_mode(o_emergency_mode), .next_press(key_next_press),
    .auto_press(key_auto_press), .settings_active(settings_active),
    .settings(picture_settings)
);

// 普通模式/应急模式控制：模式按键同步消抖、模式切换、加载仲裁、显示提交许可
emergency_mode_ctrl #(
    .INDEX_BITS(INDEX_BITS),.RESOURCE_ENABLE(RESOURCE_ENABLE),
    .REMOTE_ENABLE(REMOTE_ENABLE),
    .CLK_FREQ_HZ          (CLK_FREQ_HZ),
    .DEBOUNCE_MS          (20),
    .EMERGENCY_INDEX      (EMERGENCY_SLOT),
    .EMERGENCY_MIN_IMAGES (RESOURCE_ENABLE?1:4),
    .NORMAL_ROTATE_COUNT  (RESOURCE_ENABLE?16:3)
) u_emergency_mode_ctrl (
    .clk                   (clk),
    .rst                   (rst),
    .remote_valid          (command_valid),
    .remote_code           (command_code),
    .remote_value          (RESOURCE_ENABLE?{1'b0,command_value}:command_value[2:0]),
    .auto_play_active      (auto_play_active),
    .key_mode              (key_mode),
    .key_next_press        (key_next_press | remote_next),
    .key_auto_press        (key_auto_press),
    .pause_rotate          (settings_active),
    .scan_done             (scan_done || (scan_paused && !first_image_committed)),
    .bmp_ready             (bmp_ready && reader_bank_safe),
    .first_image_committed (first_image_committed),
    .display_valid         (display_valid),
    .load_busy             (load_busy),
    .img_found_count       (img_found_count),
    .cur_img_idx           (img_idx),
    .resource_count        (resource_active_count),.retry_emergency(retry_emergency),
    .resource_hold_seconds (resource_seconds),.hold_seconds(),
    .emergency_mode        (o_emergency_mode),
    .load_req              (ctrl_load_req),
    .load_req_idx          (ctrl_load_idx),
    .load_req_is_emergency (ctrl_load_is_emerg),
    .disp_commit_en        (ctrl_disp_commit_en)
);

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        write_ack_sync        <= 2'b00;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        source_started_seen   <= 1'b0;
        memory_done_seen      <= 1'b0;
        transition_ready_sync <= 2'b00;
        display_valid         <= 1'b0;write_started<=0;display_fallback<=0;resource_seconds<=1;retry_emergency<=0;
    end else begin
        retry_emergency<=0;
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        write_ack_sync   <= {write_ack_sync[0], write_req_ack};
        transition_ready_sync <= {transition_ready_sync[0], transition_black_ready};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (RESOURCE_ENABLE?!resource_catalog_ready:!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            source_started_seen   <= 1'b0;
            memory_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (!RESOURCE_ENABLE&&scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            // 加载请求被接受前ready仍为1；先观察busy，避免把初始idle误记为读完。
            if(load_busy&&write_req&&write_ack_sync[1])write_started<=1;
            if(load_busy&&source_started_seen&&bmp_ready&&bmp_load_failed&&!write_started)memory_done_seen<=1;
            if(load_busy && !bmp_ready) source_started_seen<=1'b1;
            if (load_busy && source_started_seen && bmp_ready)
                source_done_seen <= 1'b1;

            // 收到 write_finish_toggle 脉冲，本次 SDRAM 写事务安全结束。
            // 是否切换显示由 disp_commit_en 决定：加载性质与当前模式不一致时
            // 只结束事务、不切画面（应急期间不闪出普通图，退出应急时不闪出应急图）
            // Downscaling can finish the output frame before unused source rows
            // have drained. Latch either completion order, then wait for both.
            if (load_busy && write_finish_pulse)
                memory_done_seen <= 1'b1;
            // 保留写完成状态，等待日常转场的缓存交换许可。
            if (commit_allowed) begin
                if(RESOURCE_ENABLE&&!disp_commit_en&&(bmp_load_failed||resource_load_error)&&load_idx==EMERGENCY_SLOT&&o_emergency_mode)
                    retry_emergency<=1;
                load_busy        <= 1'b0;write_started<=0;
                source_done_seen <= 1'b0;
                source_started_seen <= 1'b0;
                memory_done_seen <= 1'b0;
                if (disp_commit_en) begin
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_fallback      <= RESOURCE_ENABLE&&resource_selected_fallback;
                    resource_seconds      <= RESOURCE_ENABLE?resource_hold_seconds:1;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                end
            end

            // 上电后自动发起一次"扫描前 4 张 BMP"
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= !RESOURCE_ENABLE;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                img_found_count       <= RESOURCE_ENABLE?({1'b0,effective_resource_count}+1'b1):0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            source_started_seen   <= 1'b0;
                memory_done_seen      <= 1'b0;
            end
            // 唯一的加载发起口：由模式控制器仲裁（首图 / 应急图 / 恢复图 / 手动 / 自动），
            // 控制器只在流水空闲时给出单周期请求，本模块据此启动一次加载事务
            else if (ctrl_load_req) begin
                write_started<=0;
                load_idx         <= ctrl_load_idx;
                load_sector      <= RESOURCE_ENABLE?0:sector_lut(ctrl_load_idx[1:0]);
                pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                load_start_pulse <= 1'b1;
                load_busy        <= 1'b1;
                source_done_seen <= 1'b0;
                source_started_seen <= 1'b0;
                memory_done_seen <= 1'b0;
            end
        end
    end
end

bmp_read #(.EARLY_FIRST_IMAGE(!RESOURCE_ENABLE),.FILE_READ_ENABLE(RESOURCE_ENABLE)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_resume            (scan_resume),
    .scan_paused            (scan_paused),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (bmp_scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (RESOURCE_ENABLE?32'd0:load_sector),

    .sd_init_done           (RESOURCE_ENABLE?resource_catalog_ready:sd_init_done),
    .file_read_error(resource_load_error),.load_failed(bmp_load_failed),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_ack_sync[1]),
    .write_ready            (write_ready),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

wire physical_sec_read,physical_sec_valid,physical_sec_end;
wire[31:0]physical_sec_addr;wire[7:0]physical_sec_data;
generate if(RESOURCE_ENABLE)begin:filesystem
 fat32_resources #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) resources(
  .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.catalog_ready(resource_catalog_ready),
  .normal_count(resource_normal_count),.active_count(resource_active_count),
  .emergency_file(resource_emergency_file),.status_flags(resource_flags),
  .select_file(load_start_pulse),.file_index(load_idx),.selected_seconds(resource_hold_seconds),.decoder_failed(bmp_load_failed),
  .load_error(resource_load_error),.selected_fallback(resource_selected_fallback),
  .virtual_read(sd_sec_read),.virtual_sector(sd_sec_read_addr),.virtual_data(sd_sec_read_data),
  .virtual_valid(sd_sec_read_data_valid),.virtual_end(sd_sec_read_end),
  .physical_read(physical_sec_read),.physical_sector(physical_sec_addr),
  .physical_data(physical_sec_data),.physical_valid(physical_sec_valid),.physical_end(physical_sec_end));
end else begin:legacy_scan
 assign physical_sec_read=sd_sec_read;assign physical_sec_addr=sd_sec_read_addr;
 assign sd_sec_read_data=physical_sec_data;assign sd_sec_read_data_valid=physical_sec_valid;assign sd_sec_read_end=physical_sec_end;
 assign resource_normal_count=0;assign resource_active_count=0;assign resource_catalog_ready=0;
 assign resource_emergency_file=0;assign resource_flags=0;assign resource_load_error=0;
 assign resource_selected_fallback=0;assign resource_hold_seconds=1;
end endgenerate

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (physical_sec_read),
    .sd_sec_read_addr       (physical_sec_addr),
    .sd_sec_read_data       (physical_sec_data),
    .sd_sec_read_data_valid (physical_sec_valid),
    .sd_sec_read_end        (physical_sec_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

// 应急、恢复、首图与失效事务绕过动画；日常交换等待转场许可。
module frame_commit_gate(
    input load_busy,source_done,memory_done,display_valid,emergency_mode,display_permit,black_ready,
    output transition_pending,commit_allowed
);
wire finished=load_busy && source_done && memory_done;
wire needs_fade=display_valid && !emergency_mode && display_permit;
assign transition_pending=finished && needs_fade;
assign commit_allowed=finished && (!needs_fade || black_ready);
endmodule

// SW2/SW3经过双级同步和消抖；拨码切换时取消尚未释放的按键事务。
// KEY2/KEY4在释放时执行一次操作，按住不连发；应急模式屏蔽调节。
module picture_key_control #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer DEBOUNCE_MS=20
)(
    input clk,rst,key_next,key_auto,emergency_mode,
    input adjustment_switch,contrast_switch,
    input remote_brightness_valid,remote_contrast_valid,
    input [2:0] remote_level,
    output reg next_press,auto_press,
    output settings_active,
    output [7:0] settings
);
wire next_down,auto_down,adjust_on,select_contrast;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) next_filter(
    .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(),.button_down(next_down));
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) auto_filter(
    .clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(),.button_down(auto_down));
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) adjust_filter(
    .clk(clk),.rst(rst),.button_in(~adjustment_switch),.press_pulse(),.button_down(adjust_on));
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) contrast_filter(
    .clk(clk),.rst(rst),.button_in(~contrast_switch),.press_pulse(),.button_down(select_contrast));
reg prev_next,prev_auto,prev_adjust,prev_contrast,prev_emergency;
reg next_blocked,auto_blocked;
reg [2:0] brightness_level,contrast_level;
wire control_changed=(prev_adjust!=adjust_on) || (prev_contrast!=select_contrast) ||
                     (prev_emergency!=emergency_mode);
assign settings_active=adjust_on && !emergency_mode;
assign settings={settings_active,select_contrast,brightness_level,contrast_level};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        prev_next<=0;prev_auto<=0;prev_adjust<=0;prev_contrast<=0;prev_emergency<=0;
        next_blocked<=0;auto_blocked<=0;next_press<=0;auto_press<=0;
        brightness_level<=2;contrast_level<=2;
    end else begin
        prev_next<=next_down;prev_auto<=auto_down;
        prev_adjust<=adjust_on;prev_contrast<=select_contrast;prev_emergency<=emergency_mode;
        next_press<=0;auto_press<=0;
        if(!next_down) next_blocked<=0;
        if(!auto_down) auto_blocked<=0;
        if(emergency_mode || control_changed || (next_down && auto_down)) begin
            if(next_down) next_blocked<=1;
            if(auto_down) auto_blocked<=1;
        end else begin
            if(prev_next && !next_down && !next_blocked) begin
                if(settings_active) begin
                    if(select_contrast) begin
                        if(contrast_level<4) contrast_level<=contrast_level+1'b1;
                    end else if(brightness_level<4) brightness_level<=brightness_level+1'b1;
                end else next_press<=1;
            end
            if(prev_auto && !auto_down && !auto_blocked) begin
                if(settings_active) begin
                    if(select_contrast) begin
                        if(contrast_level>0) contrast_level<=contrast_level-1'b1;
                    end else if(brightness_level>0) brightness_level<=brightness_level-1'b1;
                end else auto_press<=1;
            end
        end
        if(remote_brightness_valid && !emergency_mode && remote_level<=4)
            brightness_level<=remote_level;
        if(remote_contrast_valid && !emergency_mode && remote_level<=4)
            contrast_level<=remote_level;
    end
end
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output wire button_down
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;
assign button_down = !button_stable;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule

`timescale 1ns/1ps
// emergency_mode_ctrl.v
// 校园信息发布系统：普通模式 / 应急模式切换控制逻辑（纯控制、无子模块、可独立仿真）
//   - 普通模式：只在图片索引 0..2 之间轮播
//   - 应急模式：固定显示图片索引 3（EMERGENCY_INDEX）
//   - 模式按键 key_mode：2 级同步 + 20ms 消抖，一次按下只产生一个切换脉冲
//   - 应急模式下 key_next_press / key_auto_press 完全失效（不改画面、不改轮播开关）
//   - 退出应急：重新加载进入前正在显示的那张普通图，并恢复进入前的轮播状态
//   - 恢复索引只允许是"确认有效的普通图索引"：恢复未完成时再次进入应急不会把索引 3 存成恢复目标
//   - 扫描到的合法图片不足 4 张时拒绝进入应急模式，保持普通显示、不卡死
//   - 进入应急时若正在写普通图，等当前写事务结束（load_busy=0）后最高优先级加载应急图
module emergency_mode_ctrl #(
    parameter integer REMOTE_ENABLE = 0,
    parameter integer INDEX_BITS = 2,
    parameter integer RESOURCE_ENABLE = 0,
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter [INDEX_BITS-1:0] EMERGENCY_INDEX      = 2'd3,
    parameter [INDEX_BITS:0] EMERGENCY_MIN_IMAGES = 3'd4,
    parameter [INDEX_BITS:0] NORMAL_ROTATE_COUNT  = 3'd3
)(
    input             clk,
    input             rst,
    // 按键
    input             remote_valid,
    input [3:0]       remote_code,
    input [INDEX_BITS:0] remote_value,
    output            auto_play_active,
    input             key_mode,              // 原始引脚，异步，松开=1 按下=0
    input             key_next_press,        // 已消抖的"手动下一张"单周期脉冲
    input             key_auto_press,        // 已消抖的"自动轮播开关"单周期脉冲
    input             pause_rotate,
    // 系统状态（来自 sd_card_bmp.v）
    input             scan_done,             // TF 扫描已完成
    input             bmp_ready,             // BMP 解析模块就绪
    input             first_image_committed, // 首图已提交显示
    input             display_valid,         // 帧缓存中已有可显示画面
    input             load_busy,             // 正在向 SDRAM 写一帧（事务进行中）
    input [INDEX_BITS:0] img_found_count,       // 扫描到的合法图片数量(0..4)
    input [INDEX_BITS-1:0] cur_img_idx,           // 当前显示中的图片索引
    // 输出
    input [4:0] resource_count,
    input retry_emergency,
    input [5:0] resource_hold_seconds,
    output reg [5:0] hold_seconds,
    output reg        emergency_mode,        // 0=普通模式 1=应急模式
    output reg        load_req,              // 加载请求（仅在流水空闲时拉高，单周期）
    output reg [INDEX_BITS-1:0] load_req_idx,          // 请求加载的图片索引
    output reg        load_req_is_emergency, // 该请求是否为应急图
    output            disp_commit_en         // 加载完成时是否允许切换显示
);

    // ---------------- (1) 常量与自动轮播计时 ----------------
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS; // 20ms 消抖计数

    reg  [31:0] auto_cnt;
    reg[5:0]elapsed_seconds;
    wire second_tick=(auto_cnt==(CLK_FREQ_HZ-1));
    wire auto_tick=second_tick&&(elapsed_seconds+1>=hold_seconds);                 // 1Hz 自动切图节拍

    // ---------------- (2) 模式按键：2 级同步 + 消抖 + 按下沿单脉冲 ----------------
    reg        mode_sync0;
    reg        mode_sync1;
    reg        mode_stable;
    reg [31:0] mode_deb_cnt;
    reg        mode_key_press;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mode_sync0     <= 1'b1;
            mode_sync1     <= 1'b1;
            mode_stable    <= 1'b1;
            mode_deb_cnt   <= 32'd0;
            mode_key_press <= 1'b0;
        end else begin
            mode_sync0     <= key_mode;
            mode_sync1     <= mode_sync0;
            mode_key_press <= 1'b0;
            if (mode_sync1 == mode_stable) begin
                mode_deb_cnt <= 32'd0;
            end else if (mode_deb_cnt >= (DEBOUNCE_CYCLES - 1)) begin
                if (mode_stable && !mode_sync1) begin
                    mode_key_press <= 1'b1;   // 只在按下沿输出一次
                end
                mode_stable  <= mode_sync1;
                mode_deb_cnt <= 32'd0;
            end else begin
                mode_deb_cnt <= mode_deb_cnt + 32'd1;
            end
        end
    end

    // ---------------- (3) 普通模式可用轮播张数（>=3 时也只轮播 0..2） ----------------
    reg [INDEX_BITS:0] normal_count;
    always @(*) begin
        if(RESOURCE_ENABLE)normal_count=(resource_count==0)?1:resource_count;
        else if (img_found_count >= NORMAL_ROTATE_COUNT) begin
            normal_count = NORMAL_ROTATE_COUNT;
        end else begin
            normal_count = img_found_count;
        end
    end

    // ---------------- (4) 索引递增（count 为可用张数，到末页回 0） ----------------
    function [INDEX_BITS-1:0] next_index_limited;
        input [INDEX_BITS-1:0] cur;
        input [INDEX_BITS:0] count;
        begin
            case (count)
                3'd0:    next_index_limited = 2'd0;
                3'd1:    next_index_limited = 2'd0;
                default: next_index_limited = (cur >= (count - 3'd1)) ? 2'd0 : (cur + 2'd1);
            endcase
        end
    endfunction

    // ---------------- (5) 状态寄存器 ----------------
    reg [INDEX_BITS-1:0] saved_img_idx;        // 恢复目标：进入应急前确认有效的普通图索引
    reg [INDEX_BITS-1:0] last_normal_idx;      // 最近一次确认显示过的有效普通图索引（恢复索引兜底来源）
    reg       emerg_req_pending;    // 待服务：加载应急图
    reg       restore_req_pending;  // 待服务：恢复普通图
    reg       load_is_emergency;    // 当前在飞行的这次加载是否为应急图
    reg       auto_play_en;         // 自动轮播开关（应急期间保持不变）
    reg       specific_pending;
    reg [INDEX_BITS-1:0] requested_index;
    wire remote_show = REMOTE_ENABLE && remote_valid && remote_code==2;
    wire remote_auto = REMOTE_ENABLE && remote_valid && remote_code==3;
    wire remote_emergency = REMOTE_ENABLE && remote_valid && remote_code==4;
    assign auto_play_active=auto_play_en;
    reg       next_req_pending;     // 手动下一张挂起

    // ---------------- (6) 模式切换请求（组合） ----------------
    // 当前显示索引是否为"有效普通图片"：已有画面、索引落在普通轮播范围 (0..normal_count-1)、
    // 且不等于应急图索引。恢复过程中画面仍是应急图(索引 3)，该条件为假，
    // 用于阻止把索引 3 误存成普通恢复索引。
    wire disp_idx_is_normal = display_valid && (cur_img_idx < normal_count) &&
                              (cur_img_idx != EMERGENCY_INDEX);

    // 首图显示出来之前按模式键会被忽略；图片不足 4 张时恒为 0（拒绝进入）
    wire mode_enter_req = (mode_key_press || (remote_emergency && remote_value[0])) && scan_done && display_valid &&
                          !emergency_mode && (img_found_count >= EMERGENCY_MIN_IMAGES);
    wire mode_exit_req  = (mode_key_press || (remote_emergency && !remote_value[0])) && scan_done && emergency_mode;

    // ---------------- (7) 加载仲裁（优先级从高到低） ----------------
    // 所有请求都要求流水空闲（!load_busy），即当前 SDRAM 写事务已安全结束
    wire pipe_free   = scan_done && bmp_ready && !load_busy;
    wire can_first   = pipe_free && !first_image_committed && (img_found_count != 3'd0);
    wire can_emerg   = pipe_free && display_valid && (img_found_count >= EMERGENCY_MIN_IMAGES) &&
                       !mode_exit_req && (emerg_req_pending || mode_enter_req);
    // 恢复请求只在"已经退出应急"之后才允许发出：mode_exit_req 当拍 emergency_mode 仍为 1（本拍正在退出），
    // 挂起的 restore_req_pending 则必须等到 emergency_mode 已经为 0 才发出，
    // 避免快速连续切换或"切图与加载完成同拍"时误把普通图恢复进应急画面
    wire can_restore = pipe_free && display_valid &&
                       (mode_exit_req || (restore_req_pending && !emergency_mode));
    wire can_manual  = pipe_free && display_valid && !emergency_mode && !mode_enter_req && !pause_rotate &&
                       next_req_pending && (img_found_count != 3'd0);
    wire can_auto    = pipe_free && display_valid && !emergency_mode && !mode_enter_req && !pause_rotate &&
                       auto_play_en && auto_tick && (normal_count > 3'd1);

    always @(*) begin
        load_req              = 1'b0;
        load_req_idx          = 2'd0;
        load_req_is_emergency = 1'b0;
        if (can_first) begin
            load_req              = 1'b1;
            load_req_idx          = 2'd0;
            load_req_is_emergency = 1'b0;
        end else if (can_emerg) begin
            load_req              = 1'b1;
            load_req_idx          = EMERGENCY_INDEX;
            load_req_is_emergency = 1'b1;
        end else if (can_restore) begin
            load_req              = 1'b1;
            load_req_idx          = saved_img_idx;
            load_req_is_emergency = 1'b0;
        end else if (can_manual) begin
            load_req              = 1'b1;
            load_req_idx          = specific_pending ? requested_index : next_index_limited(cur_img_idx, normal_count);
            load_req_is_emergency = 1'b0;
        end else if (can_auto) begin
            load_req              = 1'b1;
            load_req_idx          = next_index_limited(cur_img_idx, normal_count);
            load_req_is_emergency = 1'b0;
        end
    end

    // ---------------- (8) 显示提交许可 ----------------
    // 只有在飞行的加载性质与当前模式期望一致时才允许切换显示：
    // 应急期间刚写完的普通图不切画面；退出应急时仍在飞行的应急图也不切画面
    wire requested_mode = mode_enter_req ? 1'b1 :
                          mode_exit_req ? 1'b0 : emergency_mode;
    assign disp_commit_en = (load_is_emergency == requested_mode);

    // ---------------- (9) 模式 / 挂起状态 ----------------
    always @(posedge clk or posedge rst) begin
        if (rst || !scan_done) begin
            // 复位或扫描未完成：强制普通模式，清除所有挂起
            emergency_mode      <= 1'b0;
            saved_img_idx       <= 2'd0;
            last_normal_idx     <= 2'd0;
            emerg_req_pending   <= 1'b0;
            restore_req_pending <= 1'b0;
            load_is_emergency   <= 1'b0;
        end else begin
            if (load_req) begin
                load_is_emergency <= load_req_is_emergency;
            end

            // 持续记录"最近一次确认显示的有效普通图索引"。
            // 恢复过程中画面仍是应急图(索引 3)，此条件为假，因此该记录不会被污染。
            if (disp_idx_is_normal) begin
                last_normal_idx <= cur_img_idx;
            end

            if (mode_enter_req) begin
                emergency_mode      <= 1'b1;
                // 仅在当前画面确认为有效普通图时才刷新恢复索引；
                // 否则沿用此前记录的有效普通索引（修复恢复未完成时再次进入应急把索引 3 存成恢复目标的缺陷）
                saved_img_idx       <= disp_idx_is_normal ? cur_img_idx : last_normal_idx;
                // 本拍已发出加载请求则无需挂起，否则挂起等流水空闲
                emerg_req_pending   <= can_emerg ? 1'b0 : 1'b1;
                restore_req_pending <= 1'b0;
            end else if (mode_exit_req) begin
                emergency_mode      <= 1'b0;
                emerg_req_pending   <= 1'b0;
                restore_req_pending <= can_restore ? 1'b0 : 1'b1;
            end else begin
                if (can_emerg) begin
                    emerg_req_pending <= 1'b0;
                end
                if (can_restore) begin
                    restore_req_pending <= 1'b0;
                end
                if(RESOURCE_ENABLE&&retry_emergency&&emergency_mode)emerg_req_pending<=1;
            end
        end
    end

    // ---------------- (10) 按键 / 自动轮播状态 ----------------
    always @(posedge clk or posedge rst) begin
        if (rst || !scan_done) begin
            auto_play_en     <= 1'b0;
            auto_cnt         <= 32'd0;elapsed_seconds<=0;hold_seconds<=RESOURCE_ENABLE?5:1;
            next_req_pending <= 1'b0;
            specific_pending <= 1'b0;requested_index<=0;
        end else begin
            // 手动下一张挂起（应急模式下被 !emergency_mode 屏蔽）
            if (mode_enter_req || pause_rotate) begin
                next_req_pending <= 1'b0;specific_pending<=0;
            end else if (remote_show && !emergency_mode && remote_value<normal_count) begin
                next_req_pending<=1;specific_pending<=1;requested_index<=remote_value[INDEX_BITS-1:0];
            end else if (key_next_press && !emergency_mode && (img_found_count != 3'd0)) begin
                next_req_pending <= 1'b1;specific_pending<=0;
            end else if (load_req && (can_manual || can_first)) begin
                next_req_pending <= 1'b0;specific_pending<=0;
            end

            // 自动轮播开关（应急模式下被 !emergency_mode 屏蔽，状态原样保留）
            if(remote_show && !emergency_mode && !mode_enter_req) begin
                auto_play_en<=0;
            end else if(remote_auto && !emergency_mode && !mode_enter_req) begin
                auto_play_en<=remote_value[0];
            end else if (key_auto_press && !emergency_mode && !mode_enter_req && (img_found_count > 3'd1)) begin
                auto_play_en <= ~auto_play_en;
            end

            // 使用成功提交画面的停留时间，失败加载不改变当前画面的计时规则。
            if(RESOURCE_ENABLE&&resource_hold_seconds!=0)hold_seconds<=resource_hold_seconds;
            // 自动轮播计时（单一赋值链）
            if (load_req) begin
                auto_cnt <= 32'd0;elapsed_seconds<=0;
            end else if (remote_auto || remote_show || (key_auto_press && !emergency_mode && ((RESOURCE_ENABLE?normal_count:img_found_count)>1))) begin
                auto_cnt <= 32'd0;elapsed_seconds<=0;
            end else if (auto_play_en && display_valid && !load_busy && first_image_committed &&
                         !emergency_mode && !pause_rotate && (normal_count > 3'd1)) begin
                if (auto_tick) begin
                    auto_cnt <= 32'd0;elapsed_seconds<=0;
                end else if(second_tick)begin
                    auto_cnt<=0;elapsed_seconds<=elapsed_seconds+1'b1;
                end else begin
                    auto_cnt <= auto_cnt + 32'd1;
                end
            end else begin
                auto_cnt <= 32'd0;elapsed_seconds<=0;
            end
        end
    end

endmodule

