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

## 串口管理扩展

uart_console.v为本项目实现的8N1收发、命令解析和状态应答模块；顶层及sd_card_bmp.v接入串口切图脉冲与操作状态反馈。电脑工具仅发送人工指令、解析状态，不承担图片或音频处理。

动态字幕字形通过tools/build_text_font.py从开发电脑Windows黑体simhei.ttf生成16×16固定ROM，未附带字体文件；字符映射表与ROM一同生成。运行期间电脑仅发送字符编号。


分级预警扩展：graded_alert_ctrl保存本地及后台等级并仲裁；共享字形ROM生成等级、选择及行动提示；音频模块增加间歇节奏，原I2S格式保持。顶层将有效等级转接到已有应急缓存控制，画面等级与实际读帧就绪关联，普通字幕缓存独立保留。

完整事件阶段新增event_packet_buffer事务、CRC16、严格重复比较与提交代次；事件字段与等级在视频帧一致呈现，源码由开发者在AI辅助下实现。event_protocol.ps1只编码字段与生成通信检错，图层渲染和仲裁在FPGA。

2026-10-07转场扩展：在现有SDRAM读通路中增加逐行地址旋转及帧参数锁存，视频层增加反馈对齐遮罩；日常默认滑出滑入，保留淡出淡入和直接切换，串口可配置。进入及解除应急均绕过动画。官方接口及加密SDRAM模块沿用现有来源。

2026-10-07相接滑动修正：将行内单缓存旋转及黑色遮罩替换为双缓存同行拼接，新图紧贴旧图进入；新增读帧代次与应急取消握手，原官方加密模块未修改。

2026-10-07资源扩展：增加fat32_resources.v，只读解析FAT32卷、短目录项、文件簇链、编号排序及可选播放列表；扩展图片索引、资源查询及失败回馈。现有官方SPI、SDRAM和HDMI底层模块沿用既有来源。FAT32字段按Microsoft FAT Specification实现，只支持本工程需要的只读子集。

2026-10-08预加载：sd_card_bmp和emergency_mode_ctrl增加下一张后台预读、缓存元数据与轮播到期保留；复用现有双帧缓存，TF带宽及应急事务排空限制见PREFETCH.md。
