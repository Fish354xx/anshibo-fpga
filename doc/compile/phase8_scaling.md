# 阶段8开发记录

## 实现

bmp_read检查BMP文件头，不再限制源图必须640x480。现有bmp_width/bmp_height端口为接口兼容保留，输出固定640x480。
SD每次完整接收512字节到扇区缓存，再由带ready握手的字节馈送器送到缩放器，避免SD读块接口无法暂停而丢字节；像素偏移可跨扇区，末尾只解析有效像素区。
bmp_nearest_scaler顺序解码BGR24，跳过行填充；用加减累加器实现floor(out_x*src_width/640)、floor(out_y*src_height/480)，不在像素路径使用除法。行缓存保存640个RGB像素，支持复用行放大和跳过行缩小，输出扫描顺序维持BMP底到顶，沿用SDRAM写入翻转。
源图范围1～1280 × 1～960。正高度无压缩RGB24 BMP，DIB头至少40字节、planes=1，像素偏移54～4096，文件长度不超过8MiB且覆盖完整行数据。非法图在开始SDRAM写事务前拒绝。图片按独立横纵比例铺满640x480，不做等比例黑边或双线性插值。
frame_read_write提供write_ready，基于写时钟域FIFO full及wrusedw<480，保留32像素余量；输出可停止，不会因连续重复行填满FIFO。
缩小可能提前输出完最后一行，再排空未采样源行；sd_card_bmp改为独立锁存内存写完与源读完，两者到齐才提交转场，避免丢失提前发生的内存完成脉冲。
文件头尺寸/长度计算增加小乘法及加法流水级，在512字节头扇区结束前稳定。未放宽时序约束。

## 测试

- tb_bmp_scaling：8x6、4x3、16x12、7x5、11x9、1x1、3x13、17x2缩放至8x6，384输出像素与独立整数除法模型逐一比对，周期性背压、各类行填充均通过。
- tb_bmp_reader_scaling：5x3且pixel_offset=600、641x481且每行填充、640x1共921600输出像素准确；SD模拟器按完整512字节无背压供给，输出端周期性暂停；扫描不同尺寸图成功。32位、压缩、过宽、过高、负高度、多planes、截断长度七类文件头均在写请求前拒绝。
- tb_picture_transition：15项通过，包含源/内存完成两种先后顺序下提交门控，以及原转场4352像素透明度组合。
- 仿真脚本：sim/run_scaling_modelsim.ps1、sim/run_reader_scaling_modelsim.ps1、sim/run_transition_modelsim.ps1。
- TD6.2.168116于2026-10-02 13:50:58完成最终bit，Setup +0.246ns，Hold +0.003ns，TNS均0。资源LUT5615/19600，REG4412/19600，BRAM9k26/64，DSP5/29。完整报告随发布保存；工程继承的官方IP警告和外部接口约束限制仍存在。

## 交付与验收

下载releases/phase8-scaling/anshibo_scaling.bit。测试图由tools/generate_scaling_test_images.py生成，位于assets/phase8_scaling_test：320x240、1280x960、641x481、640x480，分别安视播/校园公告/安全提醒/应急提示。
先用原TF素材确认兼容。再备份TF卡、确认盘符并格式化FAT32，依次复制00、01、02、03四图。检查图完整铺满、边框与网格不乱行，手动及自动轮播、应急声音、字幕、参数和转场正常。大图加载更久是预期现象。
当前未进行上板确认；用户验收后上传GitHub并创建独立标签。

## 首次上板失败与排查

用户反馈新测试图全部花屏，OSD清晰，停止轮播后仍存在。照片显示图片白色文字形成水平拖线，指向图片缓存数据/访问路径；目前不能确认根因。原anshibo_scaling.bit未验收，不提交稳定标签。
新增bmp_nearest_scaler输出等待状态，像素输出间隔至少16个100MHz周期，以排查行集中输出与共享SDRAM写突发对读取的影响。单行输出不再以50Mpixels/s集中写FIFO；保持原有FIFO余量背压。
排查文件anshibo_scaling_paced.bit于2026-10-02 14:03:55完成编译，Setup +0.114ns、Hold +0.011ns；完整读取三种尺寸共921600像素及非法头检查再次通过。等待用户在同一TF卡上验证，不能将仿真通过等同于实际花屏已修复。

## 最终上板验收通过

2026-10-02用户下载限速版本后明确确认“都正常”，阶段8验收通过，以上待确认记录属于此前排查过程。
稳定回退文件为releases/phase8-scaling/anshibo_scaling_paced.bit，标签v0.8-scaling-validated。原anshibo_scaling.bit为失败版本，仅保留作问题记录。
限速后花屏消失，支持共享存储访问负载相关推断；尚无硬件探针证据确认具体内部失效点。采用已上板通过的限速方案。
