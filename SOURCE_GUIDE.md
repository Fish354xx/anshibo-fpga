# 源代码阅读索引

VS Code打开本包，TD打开src/td_project/anshibo.al。主要RTL位于src/user_source/hdl_source/。

| 文件 | 作用 |
|---|---|
| top_tf_hdmi_audio.v | 顶层时钟、复位、接口及全部功能连接 |
| SD/sd_card_bmp.v | 图片扫描加载、缓存提交、按键调节、轮播应急控制 |
| SD/bmp_read.v | BMP头检查、解码、最近邻缩放 |
| video_rgb_to_axis_640x480.v | 视频流、OSD、颜色处理、波形快照及转场 |
| hdmi_audio_tone_i2s_64fs.v | 提示音生成和I2S发送 |
| I2S_receiver.v | 提取左右声道PCM |
| audio_arc_calculate.v | HDMI音频时钟恢复参数 |
| SD/frame_read_write.v、frame_fifo_read.v、frame_fifo_write.v | SDRAM帧缓存与FIFO数据通路 |
| SD/sd_card_top.v、sd_card_cmd.v、sd_card_sec_read_write.v、spi_master.v | TF卡SPI命令及扇区读写 |
| SD/video_timing_data.v | 视频行场时序 |
| SD/seg_scan.v、seg_decoder.v | 数码管状态 |
| IP/及src/td_project/al_ip/ | PLL、FIFO等官方IP |
| src/user_source/constraints_source/pin.adc | 引脚约束 |
| src/user_source/constraints_source/timing.sdc | 时序约束 |

按顶层、控制、画面、BMP、音频顺序阅读。.enc.v是加密官方模块，旧test/、rom/备用例程已移除。tools/generate_osd.py会重新生成部分画面代码，修改时应同步考虑生成脚本。

串口扩展：uart_console.v负责接收与发送，SD/sd_card_bmp.v负责切图仲裁；tools/launch_uart.cmd启动电脑控制工具，协议见UART_CONTROL.md。

分级阶段：graded_alert_ctrl.v管理本地按键、等级记录与后台仲裁；top_tf_hdmi_audio.v将高等级映射到原有应急缓存控制。video_rgb_to_axis_640x480.v复用动态字库显示分级模板，hdmi_audio_tone_i2s_64fs.v按等级选择间歇或持续提示。tools/build_alert_overlay.py为当前模板生成工具；不要运行旧generate_osd.py覆盖扩展画面逻辑。

事件阶段：event_packet_buffer.v负责元数据、字形、CRC及双银行事务；event_view_control负责帧安装与显示代次；event_protocol.ps1是电脑端序列化和发布向导。当前仅使用tools/build_event_layout.py统一生成警戒与事件布局，不单独运行旧generate_osd.py或build_alert_overlay.py覆盖扩展模块。

转场阶段：picture_transition管理特效和帧步进，frame_fifo_read执行行内滑动读地址，campus_osd使用实际读帧偏移遮住回绕区域。默认SLIDE，串口可选FADE/CUT；应急恢复根据当前应急图片标签绕过转场。旧generate_osd.py已加保护，避免覆盖维护后的源码。

相接滑动修正：frame_fifo_read按偏移拼接旧图行尾与新图行首，campus_osd不再遮成黑色。滑动结束及取消采用读帧代次握手，确保双缓存安全释放。视频开发继续暂停。

资源管理阶段：SD/fat32_resources.v负责只读FAT32挂载、目录簇链扫描、三位数字文件排序、播放列表、逻辑扇区映射和异常降级。sd_card_bmp.v在RESOURCE_ENABLE模式接入该模块，并扩展日常索引至16张，应急使用独立索引16；bmp_read.v继续负责BMP校验、像素与最近邻缩放。emergency_mode_ctrl以已提交画面的停留时间调度轮播。uart_console.v增加RESOURCES和SHOW 1～16；字体叠加模块增加资源不可用提示。物理SPI和SDRAM/HDMI基础接口保持既有来源。
