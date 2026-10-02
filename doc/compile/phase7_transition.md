# 阶段7：图片转场

## 实现

1. sd_card_bmp增加memory_done_seen，锁存真正SDRAM整帧写完事件。source_done_seen与memory_done_seen同时成立后才允许显示提交，等待转场期间不会丢失单周期完成脉冲。
2. frame_commit_gate仅对已有画面的普通有效事务请求转场；首图、应急图以及因模式变化而废弃的事务直接结束，不等待转场。
3. picture_transition在视频域同步pending及emergency，帧边界执行IDLE/OUT/BLACK/SETTLE/IN状态机。16帧淡出，完全黑时握手允许SD域切换缓存；pending撤销后留两个帧边界给frame_fifo_read采纳新地址，再16帧淡入。
4. RGB颜色调节后乘0～16的透明度并除16，文字在其后独立叠加，原有一像素时序延迟不变。进入应急时下一帧取消转场并恢复不透明，保留原加载及报警响应。
5. 新模块放在已有工程源码中，工具generate_osd.py可重新生成，不需要TD新增源文件。
6. 仅同步第一级添加定向false_path，颜色处理及后续同步级继续做时序检查。

## 验证

- tb_picture_transition：14项检查通过，包含源完成/内存完成区分、黑屏握手、等待确认、帧边界稳定、两帧缓存交接、应急取消、无效事务结束、首图、提前取消恢复、实际RGB输出及4352个透明度/像素值组合。
- 参数回归17项通过，包含6400个颜色组合；OSD13项完整帧验证通过；应急控制127项通过。
- 可重跑sim/run_transition_modelsim.ps1，以及已有settings/osd/controller脚本。
- TD6.2.168116于2026-10-02 13:29生成bit，最终Setup +0.140ns、Hold +0.003ns，TNS均0。时序报告随发布文件保存；结果指当前SDC覆盖范围，工程仍含官方IP警告及部分未约束接口。
- 发布：releases/phase7-transition/anshibo_transition.bit。

## 上板验收

2026-10-02用户确认本阶段上板验收通过。回退标签：v0.7-transition-validated。使用原TF卡、PROGRAM_SRAM/5MHz；检查KEY2手动转场、KEY4轮播转场、过渡期间KEY3应急及恢复、字幕和参数调节。转场本身包含有意的渐暗及短暂黑色背景，HDMI视频时序持续输出。

