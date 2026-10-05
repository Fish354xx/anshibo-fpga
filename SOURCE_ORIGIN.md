# 来源与修改范围

项目基于安路官方参考工程集成与扩展。下表列出功能实现、参考模块及官方IP。

项目新增或修改范围包括应急控制、按键调节、OSD、转场、BMP缩放与输出限速、音频提示及波形。源码由开发者在AI辅助下实现和维护，原模块沿用关系如实保留。

| 文件 | 分类 |
|---|---|
| src/td_project/al_ip/PLL_HDMI_AUDIO.v | 官方工具生成IP |
| src/td_project/al_ip/PLL_HDMI_AUDIO.vhd | 官方工具生成IP |
| src/user_source/hdl_source/I2S_receiver.v | 功能实现与适配 |
| src/user_source/hdl_source/IP/afifo_16_32_256.v | 官方工具生成IP |
| src/user_source/hdl_source/IP/afifo_32_16_256.v | 官方工具生成IP |
| src/user_source/hdl_source/IP/sys_pll.v | 官方工具生成IP |
| src/user_source/hdl_source/IP/sys_pll.vhd | 官方工具生成IP |
| src/user_source/hdl_source/IP/video_pll.v | 官方工具生成IP |
| src/user_source/hdl_source/IP/video_pll.vhd | 官方工具生成IP |
| src/user_source/hdl_source/SD/bmp_read.v | 功能实现与适配 |
| src/user_source/hdl_source/SD/color_bar.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/frame_fifo_read.v | 官方参考模块，增加实际读帧缓存标签输出 |
| src/user_source/hdl_source/SD/frame_fifo_write.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/frame_read_write.v | 功能实现与适配 |
| src/user_source/hdl_source/SD/sd_card_bmp.v | 功能实现与适配 |
| src/user_source/hdl_source/SD/sd_card_cmd.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/sd_card_sec_read_write.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/sd_card_top.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/sdram.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/seg_decoder.v | 功能实现与适配 |
| src/user_source/hdl_source/SD/seg_scan.v | 功能实现与适配 |
| src/user_source/hdl_source/SD/spi_master.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/video_define.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/video_delay.v | 沿用官方参考源码 |
| src/user_source/hdl_source/SD/video_timing_data.v | 沿用官方参考源码 |
| src/user_source/hdl_source/audio_arc_calculate.v | 功能实现与适配 |
| src/user_source/hdl_source/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v | 官方加密IP |
| src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v | 功能实现与适配 |
| src/user_source/hdl_source/hdmi_phy_warpper.v | 沿用官方参考源码 |
| src/user_source/hdl_source/include/global_def.v | 功能实现与适配 |
| src/user_source/hdl_source/include/sdr_as_ram.enc.v | 官方加密IP |
| src/user_source/hdl_source/include/sdr_init_ref.enc.v | 官方加密IP |
| src/user_source/hdl_source/include/sdr_wrrd.enc.v | 官方加密IP |
| src/user_source/hdl_source/lane_lvds_10_1.v | 沿用官方参考源码 |
| src/user_source/hdl_source/startup_pulse.v | 沿用官方参考源码 |
| src/user_source/hdl_source/top_tf_hdmi_audio.v | 功能实现与适配 |
| src/user_source/hdl_source/video_rgb_to_axis_640x480.v | 功能实现与适配 |

新增SW1叠加显示控制：顶层输入、引脚约束、两级同步、消抖及帧边界显示门控。对应测试tb/tb_overlay_switch.v。

启动优化涉及bmp_read的MBR/BPB元数据检查和跳跃、暂停与续扫，以及sd_card_bmp的首图提交与源完成握手。

应急音画启动同步：顶层新增emergency_audio_frame_gate，读缓存模块提供当前帧实际锁存编号，sd_card_bmp提供应急图片提交状态；音源等待实际应急帧有效像素开始。
