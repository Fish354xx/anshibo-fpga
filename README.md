# 安视播独立串口控制工程

在已验证显示系统基础上增加电脑文字命令，保留板载按键及拨码控制。

入口：src/td_project/anshibo.al；顶层：src/user_source/hdl_source/top_tf_hdmi_audio.v。

串口解析：src/user_source/hdl_source/uart_console.v；图片、应急及画面参数控制：src/user_source/hdl_source/SD/sd_card_bmp.v。

使用说明见UART_CONTROL.md。电脑工具tools/launch_uart.cmd，下载文件firmware/anshibo_remote.bit。先通过上板验收，再保存阶段版本。本目录未覆盖原工程及最终提交文件。

仿真：sim/run_remote_modelsim.ps1，量化及编译证据见measurements/remote_controls。串口测试使用真实100MHz及115200位时序，图像加载用模型代替，因此不能据此断言真实TF加载时间。支持TEXT更新最多64字滚动字幕，具体字符范围和协议见UART_CONTROL.md。

SOURCE_ORIGIN.md保留依赖来源说明。

