# 阶段10：Flash固化与冷启动

2026-10-02核对本地官方资料：

- D:/BaiduNetdiskDownload/HX4S20_Contest_202606/9_康芯开发板使用手册及实验平台/HX4S20开发板手册-HDL版2410.pdf 第22页启动Flash W25Q16，专用配置引脚无需RTL约束。注意文字中64M-bit容量为与型号不一致的描述；W25Q16选择16Mbits。
- D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/SWUG/SWUG110_BitWizard_User_Guide.pdf 物理第20页说明PROGRAM_FLASH将位流写到Flash、掉电不丢失；插图为Mode/Speed/MemorySize三列。Create Flash File用于多文件合并，单一bit不需要此步骤。

提供releases/phase10-poweron/anshibo_poweron.bit，与v0.9-audio-waveform-validated中的bit逐字节一致，SHA256 E3E34DAB9D187484C62DE96328456914D602E25D3FF0EA9E35EE6B1588974068，无重新编译或新RTL变更。
用户执行PROGRAM_FLASH/5MHz/16Mbits，烧写成功后通过板上电源开关完全断电重启3次，测试自动运行及现有全部功能。
2026-10-02用户在确认PROGRAM_FLASH、5MHz、16Mbits设置后反馈“没问题了”，本阶段由用户确认通过；未提供逐次重启日志。稳定回退标签：v1.0-poweron-validated。烧写将覆盖原启动镜像，回退可重新烧写任一已验收版本的bit及对应TF素材。

