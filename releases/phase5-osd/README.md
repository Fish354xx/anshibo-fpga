# 动态字幕验收版

下载anshibo_osd.bit，使用PROGRAM_SRAM，不用重新编译或改动TF卡。
显示顶部中文模式/运行时长及底部滚动中文标语，保留图片切换、自动轮播和应急声音。
TD时序Setup +0.178ns、Hold +0.011ns；ModelSim自检通过。
2026-10-02用户上板确认字幕及原有功能均正常，阶段验收通过。
回退标签：v0.5-osd-validated，包含阶段4时序优化及阶段5动态字幕。
恢复本版本时使用本目录anshibo_osd.bit；TF卡素材仍需单独保留。
