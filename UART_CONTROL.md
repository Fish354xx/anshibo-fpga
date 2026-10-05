# 安视播串口全功能控制

独立工程，原工程及最终提交目录保持原样。板载USB-UART连接电脑，115200、8N1、无流控；FPGA接收F12、发送D12。USB-JTAG仍用于下载。

下载firmware/anshibo_remote.bit。旧串口窗口输入EXIT释放COM，再启动本目录tools/launch_uart.cmd，输入COM编号。HELP显示命令。

| 命令 | 功能 |
|---|---|
| PING / STATUS | 通信检查 / 状态查询 |
| NEXT | 普通图片下一张 |
| SHOW 1 / SHOW 2 / SHOW 3 | 指定普通图片，同时停止轮播 |
| AUTO ON / AUTO OFF | 开启 / 关闭轮播 |
| EMERGENCY ON / EMERGENCY OFF | 进入 / 退出应急，第四张图片及同步报警 |
| BRIGHTNESS 0～4 / BRIGHTNESS + / BRIGHTNESS - | 设置 / 增加 / 减小亮度 |
| CONTRAST 0～4 / CONTRAST + / CONTRAST - | 设置 / 增加 / 减小对比度 |
| ADJUST ON / ADJUST OFF | 远程设置SW2调节模式 |
| SELECT BRIGHTNESS / SELECT CONTRAST | 远程设置SW3调节目标 |
| OVERLAY ON / OVERLAY OFF | 远程设置SW1，字幕波形一起显示 / 隐藏 |
| LOCAL | SW1～SW3重新由物理拨码控制 |
| RESET | 完整发送应答后复位整机，重新加载图片 |

0～4指任选一个整数，例如BRIGHTNESS 3。串口设置拨码功能后持续生效，直到LOCAL或复位。LOCAL不会重置亮度、对比度、应急或轮播状态。板载按键保留，应急期间普通切图及参数调节被拒绝。调节模式暂停轮播，退出后恢复。SHOW不选择应急图片。

## 协议

大小写不敏感，最多32个ASCII字符，以CR、LF或CRLF结束。一条命令等待应答后再发下一条。OK表示受理，尚不代表图片加载完毕。错误可能为ERR NOTREADY、EMERGENCY、ADJUST、BUSY、NOIMAGE、RANGE、CMD、LINE。

STATUS D=XXXX S=X P=XX A=X O=X R=X：D图片数[14:12]、显示索引[9:8]（从0开始）、扫描完成bit3、加载忙bit1、应急bit0；P调节模式bit7、对比度选择bit6、亮度[5:3]、对比度[2:0]；S内部控制状态；A轮播；O字幕波形；R远程控制权掩码（4字幕、2调节模式、1调节目标）。

## 更新滚动字幕

在本目录的电脑工具输入TEXT后加空格及内容，例如：

```
TEXT 今天下午14点举行消防演练，请有序离开教室
TEXT 校园通知：请保持教室卫生
TEXT Hello FPGA 2026
TEXT DEFAULT
```

前面三条替换普通模式的滚动字幕，最后一条恢复内置字幕。每条最多64个字符，支持598个字形（95个ASCII字符、503个汉字及中文标点），清单见tools/SUPPORTED_TEXT.txt。保留英文大小写。工具先检查全文，存在不支持字符或长度超限时不发送任何内容。

工具只将字符转换为内置字形编号。字幕存储、帧边界提交、字库读取、滚动及像素叠加由FPGA实现。当前字库不覆盖全部汉字，电脑无需安装Python即可操作；生成字库脚本仅在开发阶段使用。

上传期间继续显示旧字幕，成功提交后在视频帧边界整体替换，并重新从字幕起点滚动。文字不足64字时余下位置留白。应急模式仍使用原有固定安全提示，退出应急后恢复自定义内容。OVERLAY OFF隐藏自定义字幕及波形，OVERLAY ON恢复显示。RESET或断电后回到内置字幕，不持久保存新内容。

直接使用其他串口软件时，不能直接发送UTF-8中文。底层ASCII协议为TBEGIN、逐字TCHAR hhh（十六进制字形编号000～255，其中255为第598个字形）、TCOMMIT；TDEFAULT恢复默认。每个请求等待应答，字形编号必须与本版本tools/text_font.json一致。ERR TEXT表示未开启字幕上传事务，ERR RANGE表示空提交、非法字形或超过64字，ERR BUSY表示上一次提交仍待帧边界确认。可以从TBEGIN重新开始上传。

## 上板验收

依次测试指定图片、轮播、应急、亮度对比度、字幕波形，再LOCAL检查拨码恢复，最后RESET检查启动及PING恢复。保留现有四张TF图片。本阶段验收通过后保存GitHub。

