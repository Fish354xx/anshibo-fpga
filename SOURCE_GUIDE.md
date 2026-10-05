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
