# 阶段10：启动程序固化（用户已确认通过）

anshibo_poweron.bit与已上板通过的阶段9程序完全一致；SHA256 E3E34DAB9D187484C62DE96328456914D602E25D3FF0EA9E35EE6B1588974068。
本阶段只改变BitWriter烧写目标，不修改RTL、引脚或TF素材。

## 固化

1. 板子、TF卡、HDMI显示器和音响保持现有连接。
2. BitWriter列表只保留本目录anshibo_poweron.bit，Mode选PROGRAM_FLASH，Speed选5MHz，MemorySize选16Mbits。官方HX4S20手册p22指定启动Flash为W25Q16；其文中64M-bit容量描述与型号不一致，本步骤以W25Q16型号的16Mbits容量为依据。若实际板卡芯片型号不同，先核对实物。
3. 点击Run，等待软件明确报告成功后再断电。PROGRAM_FLASH将覆盖现有启动程序；已验收bit文件可再次写入以回退。单一镜像无需Create Flash File或Dual Boot。

## 验收

关闭板上电源开关，确认指示灯熄灭，等待约5秒再打开。不要再次Run，也不要按KEY1辅助启动。确认自动出现首图、字幕和波形面板，检查KEY2切图、KEY4轮播、KEY3应急/报警/波形，以及长按参数调节。
重复断电重启共3次，每次均自主运行即通过。主机USB保留用于供电可以，但不要执行SRAM下载。重启后参数2/4、轮播默认状态及运行计时重新初始化是预期行为。
若失败，记录BitWriter错误或冷启动现象并反馈，不能仅以Flash烧写成功判定启动验收通过。

依据：TD本地官方SWUG110_BitWizard_User_Guide.pdf物理第20页（正文19页）Program Flash；HX4S20开发板手册-HDL版2410.pdf第22页启动Flash。
2026-10-02用户按PROGRAM_FLASH模式操作后确认“没问题了”，本阶段确认通过。回退标签：v1.0-poweron-validated。用户未逐项提供3次重启记录。

