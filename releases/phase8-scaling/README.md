# 阶段8：不同尺寸BMP适配（已上板验收）

稳定下载文件：anshibo_scaling_paced.bit，PROGRAM_SRAM / 5MHz。
2026-10-02用户确认四张测试图显示及功能均正常。回退标签：v0.8-scaling-validated。

支持宽1～1280、高1～960的24位无压缩、正高度BMP；像素数据偏移54～4096，文件长度覆盖完整像素数据且不超过8MiB。最近邻缩放统一输出640x480，铺满屏幕，比例不同会拉伸；正确跳过每行填充字节。不支持JPEG/PNG、压缩BMP、32位BMP及负高度BMP。
测试图位于assets/phase8_scaling_test，分别320x240、1280x960、641x481、640x480。读取器按原始扇区扫描，仅支持连续存放的文件。先备份TF卡，确认盘符后格式化FAT32，再按00、01、02、03顺序逐个复制。
保留手动/自动、应急报警、字幕、参数调节和转场。大图加载较久，期间旧图保持显示。

缩放8种尺寸、完整读取3种尺寸共921600个像素、扫描及7类非法头检查通过；转场15项回归通过。稳定版Setup +0.114ns、Hold +0.011ns，TNS均0（当前SDC覆盖范围），报告为timing_report_paced.txt。
稳定bit SHA256：0E650230B0A4D4483B30DC57A104A9AF7C930F50E760CF734F85397C5ADA4009。

初版anshibo_scaling.bit出现横向拖线，不能用于稳定回退。修复版将行输出由最快每2周期一次改为每16周期一次，降低共享SDRAM写入压力；用户确认花屏消失。结果支持访问负载与花屏有关，尚未用硬件探针确认内部具体失效点。
原timing_report.txt和resource_report.txt属于失败初版记录；恢复应使用anshibo_scaling_paced.bit及本标签源码。
