
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       key_mode,           // 模式切换按键（普通/应急），原始引脚

    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output                      o_emergency_mode,   // 0=普通模式 1=应急模式（面板指示）
    output [15:0]               debug_status,
    output [7:0]                picture_settings,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

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
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              load_busy;

// 普通模式/应急模式控制器接口
wire             ctrl_load_req;        // 加载请求（仅流水空闲时拉高，单周期）
wire [1:0]       ctrl_load_idx;        // 请求加载的图片编号
wire             ctrl_load_is_emerg;   // 该请求是否为应急图
wire             disp_commit_en;       // 本次事务结束后是否允许切换显示

// bmp_ready 先表示"源文件读取/送 FIFO 完成"；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
reg [1:0]        write_ack_sync;
wire             write_finish_pulse;

assign write_en           = bmp_data_wr_en;
assign write_data         = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
// Read-only diagnostics: image count / displayed index / loading index / status flags.
assign debug_status = {1'b0, img_found_count, 2'b00, img_idx,
                       2'b00, load_idx, scan_done, bmp_ready, load_busy, o_emergency_mode};

wire settings_active;
picture_key_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_picture_keys (
    .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
    .emergency_mode(o_emergency_mode), .next_press(key_next_press),
    .auto_press(key_auto_press), .settings_active(settings_active),
    .settings(picture_settings)
);

// 普通模式/应急模式控制：模式按键同步消抖、模式切换、加载仲裁、显示提交许可
emergency_mode_ctrl #(
    .CLK_FREQ_HZ          (CLK_FREQ_HZ),
    .DEBOUNCE_MS          (20),
    .EMERGENCY_INDEX      (2'd3),
    .EMERGENCY_MIN_IMAGES (3'd4),
    .NORMAL_ROTATE_COUNT  (3'd3)
) u_emergency_mode_ctrl (
    .clk                   (clk),
    .rst                   (rst),
    .key_mode              (key_mode),
    .key_next_press        (key_next_press),
    .key_auto_press        (key_auto_press),
    .pause_rotate          (settings_active),
    .scan_done             (scan_done),
    .bmp_ready             (bmp_ready),
    .first_image_committed (first_image_committed),
    .display_valid         (display_valid),
    .load_busy             (load_busy),
    .img_found_count       (img_found_count),
    .cur_img_idx           (img_idx),
    .emergency_mode        (o_emergency_mode),
    .load_req              (ctrl_load_req),
    .load_req_idx          (ctrl_load_idx),
    .load_req_is_emergency (ctrl_load_is_emerg),
    .disp_commit_en        (disp_commit_en)
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
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        write_ack_sync   <= {write_ack_sync[0], write_req_ack};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
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
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
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
            if (load_busy && bmp_ready)
                source_done_seen <= 1'b1;

            // 收到 write_finish_toggle 脉冲，本次 SDRAM 写事务安全结束。
            // 是否切换显示由 disp_commit_en 决定：加载性质与当前模式不一致时
            // 只结束事务、不切画面（应急期间不闪出普通图，退出应急时不闪出应急图）
            if (load_busy && source_done_seen && write_finish_pulse) begin
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                if (disp_commit_en) begin
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                end
            end

            // 上电后自动发起一次"扫描前 4 张 BMP"
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end
            // 唯一的加载发起口：由模式控制器仲裁（首图 / 应急图 / 恢复图 / 手动 / 自动），
            // 控制器只在流水空闲时给出单周期请求，本模块据此启动一次加载事务
            else if (ctrl_load_req) begin
                load_idx         <= ctrl_load_idx;
                load_sector      <= sector_lut(ctrl_load_idx);
                pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                load_start_pulse <= 1'b1;
                load_busy        <= 1'b1;
                source_done_seen <= 1'b0;
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_ack_sync[1]),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

// Release-based short presses avoid issuing a normal action before recognizing a long press.
module picture_key_control #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer LONG_PRESS_MS=1000
)(
    input clk,rst,key_next,key_auto,emergency_mode,
    output reg next_press,auto_press,
    output reg settings_active,
    output [7:0] settings
);
wire next_down,auto_down;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) next_filter(
    .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(),.button_down(next_down));
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) auto_filter(
    .clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(),.button_down(auto_down));
localparam integer LONG_CYCLES=(CLK_FREQ_HZ/1000)*LONG_PRESS_MS;
reg prev_next,prev_auto,next_long,auto_long,select_contrast;
reg [31:0] next_count,auto_count;
reg [2:0] brightness_level,contrast_level;
assign settings={settings_active,select_contrast,brightness_level,contrast_level};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        prev_next<=0;prev_auto<=0;next_long<=0;auto_long<=0;
        next_count<=0;auto_count<=0;next_press<=0;auto_press<=0;
        settings_active<=0;select_contrast<=0;brightness_level<=2;contrast_level<=2;
    end else begin
        prev_next<=next_down;prev_auto<=auto_down;
        next_press<=0;auto_press<=0;
        if(!next_down) begin next_count<=0;next_long<=0;end
        if(!auto_down) begin auto_count<=0;auto_long<=0;end
        if(emergency_mode || (next_down && auto_down)) begin
            if(emergency_mode) settings_active<=0;
            next_count<=0;auto_count<=0;
            next_long<=next_down;auto_long<=auto_down;
        end else begin
            if(next_down && !next_long) begin
                if(next_count==LONG_CYCLES-1) begin
                    next_long<=1;
                    if(settings_active) select_contrast<=~select_contrast;
                end else next_count<=next_count+1'b1;
            end
            if(auto_down && !auto_long) begin
                if(auto_count==LONG_CYCLES-1) begin
                    auto_long<=1;settings_active<=~settings_active;
                end else auto_count<=auto_count+1'b1;
            end
            if(prev_next && !next_down && !next_long) begin
                if(settings_active) begin
                    if(select_contrast) begin
                        if(contrast_level<4) contrast_level<=contrast_level+1'b1;
                    end else if(brightness_level<4) brightness_level<=brightness_level+1'b1;
                end else next_press<=1;
            end
            if(prev_auto && !auto_down && !auto_long) begin
                if(settings_active) begin
                    if(select_contrast) begin
                        if(contrast_level>0) contrast_level<=contrast_level-1'b1;
                    end else if(brightness_level>0) brightness_level<=brightness_level-1'b1;
                end else auto_press<=1;
            end
        end
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
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter [1:0]   EMERGENCY_INDEX      = 2'd3,
    parameter [2:0]   EMERGENCY_MIN_IMAGES = 3'd4,
    parameter [2:0]   NORMAL_ROTATE_COUNT  = 3'd3
)(
    input             clk,
    input             rst,
    // 按键
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
    input      [2:0]  img_found_count,       // 扫描到的合法图片数量(0..4)
    input      [1:0]  cur_img_idx,           // 当前显示中的图片索引
    // 输出
    output reg        emergency_mode,        // 0=普通模式 1=应急模式
    output reg        load_req,              // 加载请求（仅在流水空闲时拉高，单周期）
    output reg [1:0]  load_req_idx,          // 请求加载的图片索引
    output reg        load_req_is_emergency, // 该请求是否为应急图
    output            disp_commit_en         // 加载完成时是否允许切换显示
);

    // ---------------- (1) 常量与自动轮播计时 ----------------
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS; // 20ms 消抖计数

    reg  [31:0] auto_cnt;
    wire        auto_tick = (auto_cnt == (CLK_FREQ_HZ - 1));                 // 1Hz 自动切图节拍

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
    reg [2:0] normal_count;
    always @(*) begin
        if (img_found_count >= NORMAL_ROTATE_COUNT) begin
            normal_count = NORMAL_ROTATE_COUNT;
        end else begin
            normal_count = img_found_count;
        end
    end

    // ---------------- (4) 索引递增（count 为可用张数，到末页回 0） ----------------
    function [1:0] next_index_limited;
        input [1:0] cur;
        input [2:0] count;
        begin
            case (count)
                3'd0:    next_index_limited = 2'd0;
                3'd1:    next_index_limited = 2'd0;
                default: next_index_limited = (cur >= (count - 3'd1)) ? 2'd0 : (cur + 2'd1);
            endcase
        end
    endfunction

    // ---------------- (5) 状态寄存器 ----------------
    reg [1:0] saved_img_idx;        // 恢复目标：进入应急前确认有效的普通图索引
    reg [1:0] last_normal_idx;      // 最近一次确认显示过的有效普通图索引（恢复索引兜底来源）
    reg       emerg_req_pending;    // 待服务：加载应急图
    reg       restore_req_pending;  // 待服务：恢复普通图
    reg       load_is_emergency;    // 当前在飞行的这次加载是否为应急图
    reg       auto_play_en;         // 自动轮播开关（应急期间保持不变）
    reg       next_req_pending;     // 手动下一张挂起

    // ---------------- (6) 模式切换请求（组合） ----------------
    // 当前显示索引是否为"有效普通图片"：已有画面、索引落在普通轮播范围 (0..normal_count-1)、
    // 且不等于应急图索引。恢复过程中画面仍是应急图(索引 3)，该条件为假，
    // 用于阻止把索引 3 误存成普通恢复索引。
    wire disp_idx_is_normal = display_valid && (cur_img_idx < normal_count) &&
                              (cur_img_idx != EMERGENCY_INDEX);

    // 首图显示出来之前按模式键会被忽略；图片不足 4 张时恒为 0（拒绝进入）
    wire mode_enter_req = mode_key_press && scan_done && display_valid &&
                          !emergency_mode && (img_found_count >= EMERGENCY_MIN_IMAGES);
    wire mode_exit_req  = mode_key_press && scan_done && emergency_mode;

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
            load_req_idx          = next_index_limited(cur_img_idx, normal_count);
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
            end
        end
    end

    // ---------------- (10) 按键 / 自动轮播状态 ----------------
    always @(posedge clk or posedge rst) begin
        if (rst || !scan_done) begin
            auto_play_en     <= 1'b0;
            auto_cnt         <= 32'd0;
            next_req_pending <= 1'b0;
        end else begin
            // 手动下一张挂起（应急模式下被 !emergency_mode 屏蔽）
            if (mode_enter_req || pause_rotate) begin
                next_req_pending <= 1'b0;
            end else if (key_next_press && !emergency_mode && (img_found_count != 3'd0)) begin
                next_req_pending <= 1'b1;
            end else if (load_req && (can_manual || can_first)) begin
                next_req_pending <= 1'b0;
            end

            // 自动轮播开关（应急模式下被 !emergency_mode 屏蔽，状态原样保留）
            if (key_auto_press && !emergency_mode && !mode_enter_req && (img_found_count > 3'd1)) begin
                auto_play_en <= ~auto_play_en;
            end

            // 自动轮播计时（单一赋值链）
            if (load_req) begin
                auto_cnt <= 32'd0;
            end else if (key_auto_press && !emergency_mode && (img_found_count > 3'd1)) begin
                auto_cnt <= 32'd0;
            end else if (auto_play_en && display_valid && !load_busy && first_image_committed &&
                         !emergency_mode && !pause_rotate && (normal_count > 3'd1)) begin
                if (auto_tick) begin
                    auto_cnt <= 32'd0;
                end else begin
                    auto_cnt <= auto_cnt + 32'd1;
                end
            end else begin
                auto_cnt <= 32'd0;
            end
        end
    end

endmodule

