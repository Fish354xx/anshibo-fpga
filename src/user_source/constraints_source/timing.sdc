
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# Only first-stage CDC registers are exempt; destination stages remain timed.
set_false_path -to [get_regs {sd_card_bmp_m0/write_ack_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/wrfin_tgl_sync[0]}]
set_false_path -to [get_regs {u_hdmi_audio_tone_i2s_64fs/enable_sync0}]
set_false_path -to [get_regs {debug_sync0[*]}]
set_false_path -to [get_regs {u_campus_osd/mode_sync0}]
set_false_path -to [get_regs {u_campus_osd/settings_sync0[*]}]
set_false_path -to [get_regs {display_valid_sync0}]
set_false_path -to [get_regs {sd_card_bmp_m0/transition_ready_sync[0]}]
set_false_path -to [get_regs {u_campus_osd/u_transition/pending_sync0}]
set_false_path -to [get_regs {u_campus_osd/u_transition/emergency_sync0}]

# Exempt only the first stage of the asynchronous SW1 synchronizer.
set_false_path -from [get_ports {subtitle_switch}] -to [get_regs {u_campus_osd/subtitle_sync0}]

# Emergency audio gate: only asynchronous input synchronizer first stages are exempt.
set_false_path -to [get_regs {u_emergency_audio_frame_gate/mode_sync0}]
set_false_path -to [get_regs {u_emergency_audio_frame_gate/loaded_sync0}]
set_false_path -to [get_regs {u_emergency_audio_frame_gate/target_sync0[*]}]
set_false_path -to [get_regs {u_emergency_audio_frame_gate/active_sync0[*]}]

# SW2/SW3: constrain the first synchronizer stage only.
set_false_path -from [get_ports {adjustment_switch}] -to [get_regs {sd_card_bmp_m0/u_picture_keys/adjust_filter/button_sync0}]
set_false_path -from [get_ports {contrast_switch}] -to [get_regs {sd_card_bmp_m0/u_picture_keys/contrast_filter/button_sync0}]

# UART RX is asynchronous; retain timing between receiver synchronizer stages.
set_false_path -from [get_ports {uart_rx}] -to [get_regs {u_uart_console/receiver/rx_sync0}]

# Software reset assertion is asynchronous. Only the reset-release synchronizers
# handle release; exempt only software-request paths ending at asynchronous reset pins.
set_false_path -from [get_regs {serial_reset_hold*}] -to [get_pins {*.sr}]




# Subtitle toggle handshake first stages and stable bundled commit metadata.
# Bank/length/enable are held until video frame-boundary acknowledgement returns.
set_false_path -to [get_regs {u_remote_text/ack_sync0}]
set_false_path -to [get_regs {u_remote_text/request_sync0}]
set_false_path -from [get_regs {u_remote_text/requested_bank u_remote_text/requested_active u_remote_text/requested_length[*]}] -to [get_regs {u_remote_text/active_bank u_remote_text/active u_remote_text/active_length[*]}]


# Graded alert asynchronous first-stage synchronizers.
set_false_path -from [get_ports {key_mode}] -to [get_regs {u_graded_alert/fm/sync0}]
set_false_path -from [get_ports {key1}] -to [get_regs {u_graded_alert/fn/sync0}]
set_false_path -to [get_regs {u_campus_osd/alert_sync0[*]}]
set_false_path -to [get_regs {u_campus_osd/candidate_sync0[*]}]
set_false_path -to [get_regs {u_campus_osd/select_sync0}]
set_false_path -to [get_regs {u_hdmi_audio_tone_i2s_64fs/level_sync0[*]}]

# Event-bank and presentation feedback toggle first stages.
set_false_path -to [get_regs {u_event_packet/ack_sync0}]
set_false_path -to [get_regs {u_event_packet/request_sync0}]
set_false_path -to [get_regs {u_event_packet/shown_sync0}]
set_false_path -to [get_regs {u_event_packet/shown_id_sync0[*]}]
set_false_path -to [get_regs {u_event_packet/shown_level_sync0[*]}]
set_false_path -to [get_regs {u_campus_osd/event_valid_sync0}]
set_false_path -to [get_regs {u_campus_osd/event_source_sync0}]
# Requested bundle is held until frame installation returns its toggle ack.
set_false_path -from [get_regs {u_event_packet/requested_*}] -to [get_regs {u_campus_osd/u_event_view/*}]
set_false_path -to [get_regs {u_event_packet/shown_generation_sync0[*]}]

# Slide request/feedback are held for a frame; constrain destination stages.
set_false_path -to [get_regs {u_campus_osd/u_transition/mode_sync0[*]}]
set_false_path -to [get_regs {u_campus_osd/u_transition/bypass_sync0}]
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/slide_sync0[*]}]
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/slide_in_sync0}]
set_false_path -to [get_regs {sd_card_bmp_m0/reader_index_sync0[*]}]

# Push transition endpoint/cancellation request and adoption feedback.
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/target_sync0[*]}]
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/mix_sync0}]
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/epoch_sync0}]
set_false_path -to [get_regs {u_campus_osd/u_transition/epoch_sync0}]
set_false_path -to [get_regs {u_campus_osd/u_transition/cancel_sync0}]
set_false_path -to [get_regs {sd_card_bmp_m0/reader_mix_sync0}]
set_false_path -to [get_regs {sd_card_bmp_m0/cancel_ack_sync0}]

# First stage only for committed resource fallback metadata.
set_false_path -to [get_regs {u_campus_osd/fallback_sync0}]
