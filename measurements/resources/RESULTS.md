# FAT32资源管理验证

日期：2026-10-07。仅记录编译与仿真通过，等待用户上板验收。

## 构建

- 固件：`firmware/anshibo_resource_manager.bit`，671528字节。
- SHA256：`D72195E66345868E21BF33D0C6412D3AAC6FEDFEA25185500DFFA523EBD76F44`。
- TD6.2.168116，EG4S20BG256，最终路由报告Setup WNS +0.112ns、Hold WNS +0.003ns。
- LUT15067/19600，寄存器8273/19600，BRAM60/64，DSP7/29。
- 保持原有时钟与约束。为满足时序将编号、卷几何、BMP检查、索引查表与逻辑扇区比较分段寄存；UART增加应答快照。资源控制采用本域同步复位，SPI和异步FIFO仍保持既有复位方式。没有豁免文件系统内部的数据路径。

## 功能证据

| 检查 | 结果与日志 |
|---|---|
| MBR FAT32、活动FAT1、根目录与NORMAL目录非连续簇链 | PASS，fat_resources.txt |
| BMP跨非连续簇，保留FAT高4位，文件头重读 | PASS，fat_resources.txt |
| 编号排序、配置顺序、重复引用、停留时间 | PASS，fat_resources.txt |
| 倒序20个文件仍选择编号最小16个 | PASS，fat_limits.txt |
| UTF8 BOM、CR/LF/CRLF、最后一行没有换行 | PASS，fat_bom.txt |
| 无分区表FAT32卷、非法扇区几何 | PASS，fat_superfloppy.txt、fat_invalid.txt |
| 缺卡、短扇区、无结束响应 | PASS，fat_no_card.txt、fat_short.txt、fat_timeout.txt |
| 非法BMP、缺目录、缺应急图、错误配置项、提前结束簇链 | PASS，fat_resources.txt |
| 16张索引、三秒计时规则、应急索引16、恢复索引15 | PASS，resource_controller.txt |
| 实际115200 UART，RESOURCES完整38字节应答，SHOW16，越界及单图片操作 | PASS，uart_resources.txt |
| 碎片文件到BMP缩放及帧提交，配置元数据同步，坏链不提交 | PASS，resource_pipeline.txt |
| 运行时应急头损坏，自动内置应急背景并可解除恢复 | PASS，resource_pipeline.txt |
| 原有远程控制、PUBLISH事件协议/显示、普通TEXT字幕 | PASS，对应resources回归日志 |

resource_pipeline验证九次完整像素输出事务，包括有效图、被拒绝的坏文件排空及内置背景；检查有效输出和背景颜色。模型提供物理扇区响应，并模拟写完成及读缓存采用，不包含真实TF卡、加密SDRAM控制器、物理HDMI接收器或扬声器。控制测试缩短计时参数，仅用于逻辑验证，不可据此报告真实启动、切图或应急响应时间。

## 重现与验收

`tools/build_fat_fixture.py`生成工作目录中的稀疏扇区数据，不访问物理磁盘；`sim/run_resources_modelsim.ps1`执行资源测试和既有功能回归。测试镜像不会打包为用户TF卡内容。

真实TF复制包在tf_resources，含四张日常图及独立应急图；PLAYLIST.TXT为可选样例，首次验收先只复制NORMAL、ALERT。上板操作见RESOURCE_MANAGEMENT.md。

应急、图片、字幕、转场及声音最终以用户上板反馈为准。旧验收标签v1.5-push-transition-validated保留。
