# v0.3-emergency-audio-validated

2026-10-02用户上板确认功能正常。
下载文件：anshibo_emergency_audio.bit。
SHA256：A520FEDE98B91AD8C336449655BAEA9D9BF209A6BF435281EA5FE0F9E6EAC0D1。

普通模式静音，KEY3进入应急图片并播放880Hz/660Hz交替提示音，再按KEY3退出、静音并恢复普通展示。
KEY1复位、KEY2普通手动切图、KEY4普通自动轮播；应急时KEY2/KEY4无效。
TF图片扫描顺序：安视播、校园公告、安全提醒、应急提示。TF卡内容不随Git回退。

包含六位数码管诊断显示。ModelSim音频联动检查通过，TD完整流程生成成功，实际板卡功能验收通过。
建立时间仍有负裕量，尚未完成时序收敛。
前阶段标签v0.2-emergency-validated与基础标签v0.1-baseline保留。
