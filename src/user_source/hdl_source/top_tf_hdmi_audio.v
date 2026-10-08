// 文件：top_tf_hdmi_audio.v
// 职责：整合时钟、复位、TF帧缓存、画面处理及HDMI音视频链路。
// 来源与修改说明：参见SOURCE_ORIGIN.md。
// 时钟：系统50MHz、TF100MHz、SDRAM约41.667MHz、视频25MHz。
// 复位：外部rst_n低有效；内部rst_all高有效。各子模块按所在时钟域运行。

module top(
    input                       uart_rx,        // USB-UART CH340 TXD -> FPGA F12
    output                      uart_tx,        // FPGA D12 -> CH340 RXD
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       adjustment_switch, // SW2：1开启调节，0恢复普通按键操作
    input                       contrast_switch,   // SW3：1选择对比度，0选择亮度
    input                       subtitle_switch, // SW1：1显示文字与波形，0只显示图片
    input                       key_mode,       // KEY3：预警等级选择/确认，长按进入三级应急

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire sd_card_clk,ext_mem_clk,video_clk,hdmi_5x_clk,audio_mclk;
wire rst_all;
wire rst_sd,rst_mem,rst_video,rst_audio,rst_sys,rst_phy;
reset_domain_sync u_reset_sd(.clk(sd_card_clk),.request(rst_all),.rst(rst_sd));
reset_domain_sync u_reset_mem(.clk(ext_mem_clk),.request(rst_all),.rst(rst_mem));
reset_domain_sync u_reset_video(.clk(video_clk),.request(rst_all),.rst(rst_video));
reset_domain_sync u_reset_audio(.clk(audio_mclk),.request(rst_all),.rst(rst_audio));
reset_domain_sync u_reset_sys(.clk(clk),.request(rst_all),.rst(rst_sys));
reset_domain_sync u_reset_phy(.clk(hdmi_5x_clk),.request(rst_all),.rst(rst_phy));
wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;



wire ext_mem_clk_sft;



wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] osd_rgb;
wire osd_vs, osd_de;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire [15:0] sd_debug_status;
wire emergency_mode;
wire emergency_picture_loaded;
wire emergency_audio_enable;
wire [1:0] read_active_index;
wire [1:0] transition_mode;
wire [9:0] slide_offset,read_slide_offset;
wire slide_in,read_slide_in;
wire slide_mix,slide_epoch,read_slide_mix,read_slide_epoch;
wire transition_cancel_request,transition_cancel_ack;
wire [7:0] picture_settings;
wire uart_next;
wire [2:0] uart_next_block_reason;
wire command_valid,auto_play_active,uart_reset;
wire [3:0] command_code;
wire [4:0] command_value;
wire[4:0]resource_normal_count,resource_active_count,resource_index;
wire[5:0]resource_seconds;wire[7:0]resource_flags;
wire resource_catalog_ready,resource_emergency_file,display_fallback;
wire[1:0]local_alert_level,remote_alert_level,effective_alert_level,alert_candidate,alert_audio_level;
wire alert_selecting,alert_backend_key,alert_major_valid,alert_major_value;
wire event_cmd_valid,event_busy,event_result_valid,event_apply_valid,event_active_valid;
wire[2:0]event_cmd,event_state;wire[3:0]event_result;
wire[15:0]event_id,event_crc,event_active_id,event_active_crc,event_pending_id,event_shown_id;
wire[15:0]event_pending_generation,event_shown_generation;
wire[1:0]event_level,event_apply_level,event_active_level,event_pending_level,event_shown_level;
wire[4:0]event_area,event_active_area,event_pending_area;
wire[6:0]event_body,event_active_body,event_pending_body,event_read_index;
wire[9:0]event_glyph,event_data;
wire event_pending,event_pending_bank,event_install,event_read_bank,event_shown_remote;
wire[3:0]alert_control_code=event_apply_valid?4'd13:command_code;
wire[2:0]alert_control_value=event_apply_valid?{1'b0,event_apply_level}:command_value[2:0];
wire alert_control_valid=event_apply_valid||command_valid;
event_packet_buffer u_event_packet(
 .clk(sd_card_clk),.rst(rst_sd),.cmd_valid(event_cmd_valid),.cmd(event_cmd),
 .event_id(event_id),.check_crc(event_crc),.level(event_level),.area_length(event_area),.body_length(event_body),.glyph(event_glyph),
 .ready(uart_next_block_reason!=1),.major_available(resource_catalog_ready),
 .legacy_change(command_valid&&(command_code==4||command_code==13)),.local_level(local_alert_level),
 .result_valid(event_result_valid),.result(event_result),.apply_valid(event_apply_valid),.apply_level(event_apply_level),
 .active_valid(event_active_valid),.active_id(event_active_id),.active_crc(event_active_crc),.active_level(event_active_level),
 .active_area_length(event_active_area),.active_body_length(event_active_body),.busy(event_busy),.event_state(event_state),
 .video_clk(video_clk),.video_rst(rst_video),.install(event_install),
 .shown_remote(event_shown_remote),.shown_id(event_shown_id),.shown_level(event_shown_level),
 .shown_generation(event_shown_generation),
 .video_pending(event_pending),.pending_bank(event_pending_bank),.pending_id(event_pending_id),.pending_level(event_pending_level),
 .pending_generation(event_pending_generation),
 .pending_area_length(event_pending_area),.pending_body_length(event_pending_body),
 .read_bank(event_read_bank),.read_index(event_read_index),.read_glyph(event_data));
wire alert_picture_ready,alert_restore_ready;
wire sd_command_valid=alert_major_valid || (command_valid&&command_code!=4&&command_code!=13);
wire[3:0]sd_command_code=alert_major_valid?4'd4:command_code;
wire[4:0]sd_command_value=alert_major_valid?{4'b0,alert_major_value}:command_value;
graded_alert_ctrl u_graded_alert(
 .clk(sd_card_clk),.rst(rst_sd),.key_mode(key_mode),.key_next(key1),
 .ready(uart_next_block_reason!=1),.major_available(resource_catalog_ready),
 .command_valid(alert_control_valid),.command_code(alert_control_code),.command_value(alert_control_value),
 .backend_major(emergency_mode),.local_level(local_alert_level),.remote_level(remote_alert_level),
 .effective_level(effective_alert_level),.selecting(alert_selecting),.candidate(alert_candidate),
 .backend_next_key(alert_backend_key),.major_command_valid(alert_major_valid),.major_command_value(alert_major_value));
wire [9:0] text_glyph,text_read_glyph;
wire text_ready,text_open,text_active,text_changed,text_frame_start;
wire [6:0] text_length;
wire [5:0] text_read_index;
remote_text_buffer u_remote_text(
 .write_clk(sd_card_clk),.write_rst(rst_sd),.command_valid(command_valid),
 .command_code(command_code),.glyph(text_glyph),.ready(text_ready),
 .transaction_open(text_open),.length(text_length),.video_clk(video_clk),.video_rst(rst_video),
 .frame_start(text_frame_start),.read_index(text_read_index),
 .active(text_active),.changed(text_changed),.read_glyph(text_read_glyph));
wire overlay_override,overlay_value,adjust_override,adjust_value,select_override,select_value;
wire effective_overlay=overlay_override ? overlay_value : subtitle_switch;
wire effective_adjust=adjust_override ? adjust_value : adjustment_switch;
wire effective_select=select_override ? select_value : contrast_switch;
wire physical_reset;
reg [7:0] serial_reset_hold;
always @(posedge sd_card_clk or posedge physical_reset) begin
    if(physical_reset) serial_reset_hold<=0;
    else if(uart_reset) serial_reset_hold<=8'hFF;
    else if(serial_reset_hold!=0) serial_reset_hold<=serial_reset_hold-1'b1;
end
// 与TF控制同100MHz域，无需跨域传递命令脉冲。
uart_console #(.CLK_FREQ_HZ(100_000_000),.BAUD(115200),.EXTENDED_STATUS(1),.GRADED_ALERT_ENABLE(1),.EVENT_ENABLE(1),.TRANSITION_ENABLE(1),.RESOURCE_ENABLE(1)) u_uart_console(
    .clk(sd_card_clk),.rst(rst_sd),.rx(uart_rx),.tx(uart_tx),
    .next_block_reason(uart_next_block_reason),.debug_status(sd_debug_status),
    .resource_normal_count(resource_normal_count),.resource_active_count(resource_active_count),
    .resource_index(resource_index),.resource_seconds(resource_seconds),.resource_flags(resource_flags),
    .resource_ready(resource_catalog_ready),.resource_emergency_file(resource_emergency_file),
    .state_code(state_code),.picture_settings(picture_settings),.next_pulse(uart_next),
    .command_valid(command_valid),.command_code(command_code),.command_value(command_value),
    .auto_status(auto_play_active),.overlay_status(effective_overlay),.soft_reset(uart_reset),
    .text_ready(text_ready),.text_open(text_open),.text_length(text_length),.text_glyph(text_glyph),
    .effective_alert(effective_alert_level),.local_alert(local_alert_level),.remote_alert(remote_alert_level),
    .event_busy(event_busy),.event_result_valid(event_result_valid),.event_result(event_result),
    .event_active_valid(event_active_valid),.event_active_id(event_active_id),.event_active_crc(event_active_crc),
    .event_active_level(event_active_level),.event_state(event_state),.event_active_area(event_active_area),.event_active_body(event_active_body),
    .event_cmd_valid(event_cmd_valid),.event_cmd(event_cmd),.event_id(event_id),.event_crc(event_crc),.event_level(event_level),
    .event_area(event_area),.event_body(event_body),.event_glyph(event_glyph),
    .overlay_override(overlay_override),.overlay_value(overlay_value),
    .adjust_override(adjust_override),.adjust_value(adjust_value),
    .select_override(select_override),.select_value(select_value),.transition_mode(transition_mode));
wire transition_pending,transition_black_ready;
wire sd_card_write_ready;
reg [19:0] debug_sync0, debug_sync1;
wire [6:0] debug_seg_count, debug_seg_display, debug_seg_load;
wire [6:0] debug_seg_flags, debug_seg_mode;
always @(posedge clk or posedge rst_sys) begin
    if (rst_sys) begin
        debug_sync0 <= 20'd0;
        debug_sync1 <= 20'd0;
    end else begin
        debug_sync0 <= {state_code, sd_debug_status};
        debug_sync1 <= debug_sync0;
    end
end
seg_decoder debug_count(.bin_data(debug_sync1[15:12]), .seg_data(debug_seg_count));
seg_decoder debug_display(.bin_data(debug_sync1[11:8]), .seg_data(debug_seg_display));
seg_decoder debug_load(.bin_data(debug_sync1[7:4]), .seg_data(debug_seg_load));
seg_decoder debug_flags(.bin_data(debug_sync1[3:0]), .seg_data(debug_seg_flags));
seg_decoder debug_mode(.bin_data({3'b000,debug_sync1[0]}), .seg_data(debug_seg_mode));

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;

wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
assign physical_reset = ~rst_n | ~audio_pll_lock;
assign rst_all = physical_reset | (serial_reset_hold!=0);

// TF读取、SDRAM访问与视频输出使用独立时钟域
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 沿用官方音频PLL配置；CLKC2实际为12.295082MHz，采样率约48.028kHz
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .REMOTE_ENABLE     (1),
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4),
    .FRAME_READER_FEEDBACK(1),.RESOURCE_ENABLE(1),.PREFETCH_ENABLE(1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .command_valid     (sd_command_valid),
    .command_code      (sd_command_code),
    .command_value     (sd_command_value),
    .auto_play_active  (auto_play_active),
    .resource_normal_count(resource_normal_count),.resource_active_count(resource_active_count),
    .resource_index(resource_index),.resource_seconds(resource_seconds),.resource_flags(resource_flags),
    .resource_catalog_ready(resource_catalog_ready),.resource_emergency_file(resource_emergency_file),
    .display_fallback(display_fallback),
    .remote_next       (uart_next),
    .next_block_reason (uart_next_block_reason),
    .key_next          (alert_backend_key),
    .key_auto          (key2),
    .key_mode          (1'b1),
    .adjustment_switch (effective_adjust),
    .contrast_switch   (effective_select),
    .debug_status      (sd_debug_status),
    .o_emergency_mode  (emergency_mode),
    .o_emergency_loaded(emergency_picture_loaded),
    .picture_settings  (picture_settings),
    .transition_pending(transition_pending),
    .transition_black_ready(transition_black_ready),
    .read_active_index_async(read_active_index),
    .read_slide_mix_async(read_slide_mix),.transition_cancel_request(transition_cancel_request),
    .transition_cancel_ack_async(transition_cancel_ack),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (sd_card_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (debug_sync1[19:16]),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,debug_seg_count}),
    .seg_data_1        ({1'b1,debug_seg_display}),
    .seg_data_2        ({1'b1,debug_seg_load}),
    .seg_data_3        ({1'b1,debug_seg_flags}),
    .seg_data_4        ({1'b1,debug_seg_mode}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// Transfer the slow display-valid flag into the pixel clock domain before RGB gating.
reg display_valid_sync0, display_valid_sync1;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        display_valid_sync0 <= 1'b0;
        display_valid_sync1 <= 1'b0;
    end else begin
        display_valid_sync0 <= display_valid;
        display_valid_sync1 <= display_valid_sync0;
    end
end
assign vout_data = display_valid_sync1 ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480),
    .SLIDE_ENABLE     (1)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_active_index (read_active_index),
    .slide_offset(slide_offset),.slide_in(slide_in),
    .slide_target_index(write_buf_idx),.slide_mix(slide_mix),.slide_epoch(slide_epoch),
    .read_slide_mix(read_slide_mix),.read_slide_epoch(read_slide_epoch),
    .read_slide_offset(read_slide_offset),.read_slide_in(read_slide_in),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_ready       (sd_card_write_ready)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// 音频仅在应急图所用缓存实际进入有效视频帧后启动，退出应急及时静音。
emergency_audio_frame_gate u_emergency_audio_frame_gate(
    .clk(video_clk),.rst(rst_video),.vs(vs),.de(de),
    .mode_async(emergency_mode),.loaded_async(emergency_picture_loaded),
    .target_index_async(disp_buf_idx),.active_index_async(read_active_index),
    .audio_enable(emergency_audio_enable),.picture_ready(alert_picture_ready),.restore_ready(alert_restore_ready));
// ===================== 音频：应急双音提示，普通模式发送静音采样 =====================
hdmi_audio_tone_i2s_64fs #(
    .GRADED_ENABLE(1),
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_audio),
    .I_enable    (emergency_audio_enable),
    .I_alert_level(alert_audio_level),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_video),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
campus_osd #(.DYNAMIC_TEXT_ENABLE(1),.GRADED_ALERT_ENABLE(1),.EVENT_ENABLE(1),.SLIDE_ENABLE(1),.RESOURCE_ENABLE(1)) u_campus_osd(
    .clk(video_clk), .rst(rst_video), .in_vs(vs), .in_de(de),
    .in_rgb(vout_data), .emergency_async(emergency_mode),
    .transition_pending_async(transition_pending), .transition_black_ready(transition_black_ready),
    .transition_mode_async(transition_mode),
    .transition_bypass_async(emergency_mode || emergency_picture_loaded || effective_alert_level>=2),
    .read_slide_offset_async(read_slide_offset),.read_slide_in_async(read_slide_in),
    .slide_offset(slide_offset),.slide_in(slide_in),
    .read_slide_epoch_async(read_slide_epoch),.transition_cancel_request_async(transition_cancel_request),
    .slide_mix(slide_mix),.slide_epoch(slide_epoch),.transition_cancel_ack(transition_cancel_ack),
    .resource_fallback_async(display_fallback),
    .subtitle_enable_async(effective_overlay), .settings_async(picture_settings),
    .dynamic_text_active(text_active),.dynamic_text_changed(text_changed),
    .alert_level_async(effective_alert_level),.alert_select_async(alert_selecting),.alert_candidate_async(alert_candidate),
    .alert_picture_ready(alert_picture_ready),.alert_restore_ready(alert_restore_ready),
    .event_valid_async(event_active_valid),.event_remote_wins_async(remote_alert_level>local_alert_level),
    .event_pending(event_pending),.event_pending_bank(event_pending_bank),.event_pending_id(event_pending_id),
    .event_pending_generation(event_pending_generation),
    .event_pending_level(event_pending_level),.event_pending_area(event_pending_area),.event_pending_body(event_pending_body),
    .event_data(event_data),.event_install(event_install),.event_read_bank(event_read_bank),.event_read_index(event_read_index),
    .event_shown_remote(event_shown_remote),.event_shown_id(event_shown_id),.event_shown_level(event_shown_level),
    .event_shown_generation(event_shown_generation),
    .alert_audio_level(alert_audio_level),
    .dynamic_text_glyph(text_read_glyph),.dynamic_text_index(text_read_index),
    .dynamic_frame_start(text_frame_start),
    .audio_valid(audio_valid), .audio_sample(audio_left_data),
    .out_vs(osd_vs), .out_de(osd_de), .out_rgb(osd_rgb)
);
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
    .I_rgb         (osd_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_phy),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule

// 应急音画启动门控。缓存标签来自读控制器实际锁存值，而不是加载请求。
// 异步标志和缓冲编号经两级同步，首次有效像素前检查匹配；不改变视频数据路径。
module emergency_audio_frame_gate(
    input clk,rst,vs,de,mode_async,loaded_async,
    input [1:0] target_index_async,active_index_async,
    output reg audio_enable,
    output picture_ready,restore_ready
);
reg mode_sync0,mode_sync1,loaded_sync0,loaded_sync1,loaded_sync2;
reg [1:0] target_sync0,target_sync1,active_sync0,active_sync1;
reg vs_prev,first_pixel_pending;
assign picture_ready=mode_sync1&&loaded_sync2&&(active_sync1==target_sync1);
assign restore_ready=!mode_sync1&&!loaded_sync2&&(active_sync1==target_sync1);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        mode_sync0<=0;mode_sync1<=0;loaded_sync0<=0;loaded_sync1<=0;loaded_sync2<=0;
        target_sync0<=0;target_sync1<=0;active_sync0<=0;active_sync1<=0;
        vs_prev<=0;first_pixel_pending<=0;audio_enable<=0;
    end else begin
        mode_sync0<=mode_async;mode_sync1<=mode_sync0;
        loaded_sync0<=loaded_async;loaded_sync1<=loaded_sync0;loaded_sync2<=loaded_sync1;
        target_sync0<=target_index_async;target_sync1<=target_sync0;
        active_sync0<=active_index_async;active_sync1<=active_sync0;
        vs_prev<=vs;
        if(vs && !vs_prev) first_pixel_pending<=1;
        else if(de && first_pixel_pending) first_pixel_pending<=0;
        if(!mode_sync1 || !loaded_sync2) audio_enable<=0;
        else if(de && first_pixel_pending)
            audio_enable<=(active_sync1==target_sync1);
    end
end
endmodule

// 异步置位、两级同步释放；软件复位不直接跨域解除。
module reset_domain_sync(input clk,request,output rst);
reg [1:0] release_pipe;
always @(posedge clk or posedge request) begin
 if(request)release_pipe<=2'b11;
 else release_pipe<={release_pipe[0],1'b0};
end
assign rst=release_pipe[1];
endmodule

