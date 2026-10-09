from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
letter=A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'submission/technical_document'
OUT.mkdir(parents=True,exist_ok=True)
pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/simhei.ttf'))
pdfmetrics.registerFont(TTFont('Song','C:/Windows/Fonts/simsun.ttc',subfontIndex=0))
styles={
 'title':ParagraphStyle('title',fontName='CN',fontSize=30,leading=49,spaceAfter=13,alignment=TA_CENTER,textColor=colors.black),
 'h1':ParagraphStyle('h1',fontName='CN',fontSize=17,leading=24,spaceAfter=12,textColor=colors.black),
 'h2':ParagraphStyle('h2',fontName='CN',fontSize=15,leading=20,spaceBefore=10,spaceAfter=5,keepWithNext=True,textColor=colors.black),
 'body':ParagraphStyle('body',fontName='Song',fontSize=12,leading=20,firstLineIndent=24,spaceAfter=8,wordWrap='CJK'),
 'cell':ParagraphStyle('cell',fontName='Song',fontSize=10,leading=14,wordWrap='CJK'),
 'small':ParagraphStyle('small',fontName='CN',fontSize=8.5,leading=13,spaceAfter=6,wordWrap='CJK')}
story=[];md=[]
def para(t,kind='body'):
 story.append(Paragraph(escape(t).replace('\n','<br/>'),styles[kind]));md.append(({'title':'# ','h1':'## ','h2':'### '}.get(kind,''))+t+'\n')
def heading(t):para(t,'h2')
def page(t):
 if story:story.append(PageBreak())
 para(t,'h1');md.append('---\n')
def table(headers,rows,widths):
 data=[[Paragraph(escape(str(v)),styles['cell']) for v in row] for row in [headers]+rows]
 t=Table(data,colWidths=widths,repeatRows=1,hAlign='LEFT')
 t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#E7EDF2')),('GRID',(0,0),(-1,-1),.5,colors.HexColor('#D9D9D9')),('VALIGN',(0,0),(-1,-1),'MIDDLE'),('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8)]))
 story.extend([t,Spacer(1,9)])
 md.append('| '+' | '.join(headers)+' |\n');md.append('| '+' | '.join(['---']*len(headers))+' |\n');md.extend(['| '+' | '.join(map(str,row))+' |\n' for row in rows])
def diagram():
 d=Drawing(468,186)
 labels=['TF FAT32资源','BMP解析与缩放','SDRAM双缓冲','转场与图层处理','HDMI视频输出']
 for i,label in enumerate(labels):
  x=i*94;d.add(Rect(x,113,86,49,strokeColor=colors.HexColor('#8A99A6'),fillColor=colors.HexColor('#F0F4F7')))
  # Split labels where needed.
  a,b={'TF FAT32资源':('TF卡','FAT32资源'),'BMP解析与缩放':('BMP解析','最近邻缩放'),'SDRAM双缓冲':('SDRAM','双缓冲预读'),'转场与图层处理':('转场拼接','参数与图层'),'HDMI视频输出':('HDMI','视频输出')}[label]
  d.add(String(x+43,143,a,fontName='CN',fontSize=9,textAnchor='middle'));d.add(String(x+43,128,b,fontName='CN',fontSize=9,textAnchor='middle'))
  if i<4:d.add(Line(x+86,137,x+94,137,strokeColor=colors.black))
 d.add(Rect(0,29,180,47,strokeColor=colors.HexColor('#8A99A6'),fillColor=colors.white));d.add(String(90,58,'按键与可选串口事件',fontName='CN',fontSize=10,textAnchor='middle'));d.add(String(90,42,'等级仲裁  CRC校验  帧边界提交',fontName='CN',fontSize=9,textAnchor='middle'))
 d.add(Rect(220,29,248,47,strokeColor=colors.HexColor('#8A99A6'),fillColor=colors.white));d.add(String(344,58,'FPGA音源  I2S  HDMI音频',fontName='CN',fontSize=10,textAnchor='middle'));d.add(String(344,42,'应急帧门控与波形叠加',fontName='CN',fontSize=9,textAnchor='middle'))
 d.add(Line(180,52,220,52));d.add(Line(90,76,90,100));d.add(Line(90,100,326,100));d.add(Line(326,100,326,113));story.append(d)
 md.append('TF FAT32 → BMP解析与缩放 → SDRAM双缓冲预读 → 转场与图层处理 → HDMI；按键与事件控制显示和音频。\n')

para('安视播','title')
para('校园电子广告牌兼容应急信息发布系统','h1')
para('技术说明文档','h1')
story.append(Spacer(1,70))
para('开发板型号  HX4S20C','h2')
para('主芯片  EG4S20BG256','h2')
para('开发工具  Anlogic TD 6.2.1','h2')
para('文档日期  2026年10月','h2')
story.append(Spacer(1,70))
para('选题一  基于安路EG4S20的HDMI多媒体播放系统','small')
para('本报告以当前已验证预加载固件及最终源码为依据，按设计参考文档的章节组织，说明系统原理、模块接口与操作方法。','small')
page('目录')
table(['章节','内容','页码'],[
['1','概述','3'],['2','功能与原理','4'],['2.1','HDMI显示与音频链路','4'],['2.2','TF资源与BMP读取','5'],['2.3','系统架构与时钟结构','6'],['2.4','缩放 转场与图层处理','7'],['2.5','分级预警与音画联动','8'],['2.6','可选串口发布','8'],['3','模块接口','9'],['3.1','顶层模块','9'],['3.2','TF与BMP模块','10'],['3.3','HDMI视频与发射模块','11'],['3.4','FIFO与SDRAM模块','12'],['3.5','音频与应急门控模块','12'],['4','实验步骤','13'],['4.1','连接与资源准备','13'],['4.2','编译 固化与操作','13'],['4.3','功能测试与实现结果','14'],['4.4','异常检查与交付说明','15']],[45,365,58])
page('1 概述')
para('安视播面向教学楼、校园公共大厅和实验室入口的信息展示与应急提示。系统以FPGA为核心，从TF卡读取校园海报、课程占用安排、活动通知及安全提示，输出HDMI画面；发生预警时显示分级信息，并按等级输出提示音。')
para('日常信息与应急资源角色独立。NORMAL目录支持最多16张合法BMP，ALERT/EVAC.BMP固定作为应急底图。修改合规素材或可选播放列表后重新上电即可生效，不需要修改RTL或重新烧录。')
heading('主要功能')
table(['功能','实现方式'],[['资源与轮播','FAT32只读目录和簇链解析，编号排序与可选播放列表'],['图像适配','RGB24无压缩BMP，最近邻缩放至640×480'],['缓存与转场','两帧SDRAM缓存、下一张预加载、SLIDE/FADE/CUT'],['图层与参数','滚动字幕、运行时间、状态、五档亮度与对比度'],['应急与音频','三级预警，本地优先，提示音与应急显示帧门控'],['额外管理','串口更新普通字幕，事务式发布等级、区域与正文']],[105,363])
heading('应用流程')
para('常态显示海报与滚动通知；一级提醒保持日常播放；二级显示警戒页并间歇发声；三级显示应急底图与疏散文字并持续交替报警。进入和解除应急均绕过动画，解除后恢复日常资源和字幕。')
para('核心图像解析、缓存、渲染、仲裁及音频生成均由FPGA实现。串口电脑作为可选发布入口，不生成展示画面；断开电脑后本地按键、轮播、调节和应急仍可运行。系统不提供火情检测或自动疏散路线规划。')
page('2 功能与原理')
heading('2.1 HDMI显示与音频链路')
para('视频和音频均通过开发板HDMI_B接口输出。HDMI链路采用三个TMDS数据通道和一个时钟通道；本系统由安路HDMI 1.4b发射IP完成视频与音频组包及编码，PHY将10位通道数据串行化输出。')
para('显示采用RGB888格式。video_timing_data生成行场同步与DE，读FIFO输出像素，经延迟对齐和campus_osd处理，再由video_rgb_to_axis_640x480转换为带帧起始、行结束和有效标志的视频流，供HDMI发射核消费。')
table(['通路','数据及用途'],[['视频输入','24位RGB，DE有效区为640×480'],['视频流标志','user表示帧起始，last表示行结束，valid表示有效像素'],['音频输入','24位左右声道PCM及样本有效'],['音频时钟恢复','N=6144，CTS按样本节拍和视频时钟计算'],['DDC','启动触发EDID读取，输出SCL及双向SDA'],['物理输出','TMDS的CLK/D0/D1/D2，约束绑定HDMI_B']],[130,338])
heading('音频与终端条件')
para('提示音由FPGA相位累加器生成，经过I2S发送、I2S_receiver接收及ACR参数计算进入HDMI核。普通模式输出静音，音频时钟与零样本传输仍持续，不从TF读取音频文件。')
para('需要支持HDMI音频的显示或音频接收设备。若显示器通过自身音频输出接音箱，应启用HDMI声音并检查音量；单独将音箱连接电脑不能播放开发板HDMI音频。')
para('当前有效区640×480，总时序800×525，像素时钟25 MHz，刷新率约59.52 Hz。帧缓存完整后才允许显示图片，首图加载等待不等于HDMI链路故障。')
page('2.2 TF资源与BMP读取')
para('TF卡使用FAT32、512字节扇区。fat32_resources检查卷几何与活动FAT，读取根目录及资源子目录，沿文件簇链映射逻辑扇区；支持MBR分区和无分区表卷，图片不必连续存放。')
table(['路径','约定'],[['NORMAL/NNN.BMP','编号000至999，最多16张合法日常图，默认编号顺序'],['ALERT/EVAC.BMP','独立应急底图，不占日常图片名额'],['PLAYLIST.TXT','可选，最多512字节和16条；如001.BMP,5，停留1至60秒']],[150,318])
para('仅使用8.3短文件名，不支持中文长文件名、exFAT或运行中热更新。未配置有效播放列表时按编号排序，每张默认停留5秒。列表可改变顺序、重复引用或选取部分图片，SHOW选择的是播放条目，不是文件名编号。')
heading('BMP头与像素数据')
para('bmp_read检查BM标识、数据偏移、位深、压缩与尺寸，只接收正高度24位无压缩BMP，宽1至1280、高1至960。典型文件头14字节、信息头40字节，实际读取以头中数据偏移为准，不把所有文件的像素起点强制固定为54字节。')
para('像素采用BGR字节排列，解析后转换为RGB。行字节数为4×ceil(3×W/4)，包含4字节对齐填充。正高度BMP自底向上保存，内存写地址进行垂直翻转，使显示方向正确。')
heading('读取与降级')
para('非法BMP头不进入资源索引。加载时，源处理完成与内存整帧写完成必须同时成立，才能提交新画面；写侧通过write_ready背压，缩放输出设置节拍间隔。')
para('无日常资源显示内置背景和资源提示；无应急底图仍保留预警文字与提示音。坏簇或提前结束时排空无效写事务，保持旧画面或改用内置背景。目录有扫描上限，不修复TF文件系统。')
page('2.3 系统架构与时钟结构')
diagram()
para('图1 系统数据与控制结构','small')
para('视频链路为TF读取、BMP解析缩放、写FIFO、SDRAM、读FIFO、视频时序及叠加、AXI视频流、HDMI发射核与PHY。音频生成和交互控制为并行通路。')
table(['时钟','当前用途'],[['50 MHz clk','板载输入参考'],['100 MHz sd_card_clk','TF资源索引、BMP与控制'],['约41.667 MHz ext_mem_clk','SDRAM用户缓存访问'],['25 MHz video_clk','像素、图层与视频输入'],['125 MHz hdmi_5x_clk','TMDS串行发送'],['约12.295082 MHz audio_mclk','I2S与提示音']], [160,308])
para('写FIFO在100 MHz与内存域之间传输，读FIFO在内存与视频域之间传输。请求确认、完成翻转及缓存标签通过同步器传递；整帧提交、转场取消和旧缓存释放由握手协调，避免覆盖仍在显示的帧。')
heading('双缓冲与预读')
para('每帧640×480=307200个32位字，两个区域的基地址分别为0和307200，两帧共2457600字节。显示当前帧时预读下一张；缓存命中后直接转场，未命中则读取指定文件。预读不提高TF带宽，到期但尚未完成时仍显示旧图并保留切换请求。')
para('相接滑动时两帧同时被读，完成读端释放后才可重写旧帧。应急请求优先；正在写入的普通预读先安全排空，再服务应急，因此可能增加紧急切换等待。')
page('2.4 缩放 转场与图层处理')
heading('最近邻缩放')
para('目标坐标(x,y)对应源像素xs=floor(x×W/640)、ys=floor(y×H/480)。流式行缓存按坐标累计关系采样、丢弃或重复行，输出640×480。算法成本较低；不提供双线性插值或缩小时抗混叠，非4:3图片直接拉伸。')
heading('相接滑动与可选特效')
para('设水平偏移d，x<640-d时读取旧图x+d，否则读取新图x-(640-d)。两段同行拼接填满整行，没有黑色画面夹在两图之间。每视频帧推进40像素，16步运动约268.8 ms；加载和缓存采用时间另计。')
para('默认SLIDE，FADE为淡出后淡入，CUT直接切换。进入和解除二、三级预警旁路动画，但仍等待完整图片和读缓存就绪，不属于零延迟切屏。')
heading('亮度 对比度与OSD')
para('单通道Cout=clamp(g×(Cin-128)+128+b,0,255)。对比度五档增益为0.5、0.75、1、1.25、1.5，亮度五档偏移为-64、-32、0、32、64，默认均为第2档索引；采用移位、加法和饱和裁剪。')
para('图片处理后叠加状态、运行时长、通知和波形。SW1控制普通文字与波形，SW2开启调节，SW3选择对比度或亮度；参数显示与当前设置一致。时间表示运行时长，不是日期或实时时钟。')
heading('动态文字与音频波形')
para('字库共607个字形，包含95个ASCII字符及512个汉字和中文标点。普通字幕最多64字符，备用银行接收后在帧边界整体替换。滚动偏移按视频帧推进，不随图片转场一起平移。')
para('内部PCM样本保存为波形快照并映射到屏幕坐标。日常静音时波形接近基线；没有外部麦克风采集或FFT频谱分析。')
page('2.5 分级预警与音画联动')
table(['等级','画面','声音'],[['一级','提示叠加，日常播放继续','静音'],['二级','警戒页与区域、正文','间歇约880 Hz'],['三级','EVAC应急底图与疏散信息','约660/880 Hz交替']], [50,268,150])
para('本地与后台等级独立记录，较高等级优先，同级本地优先。KEY3选择和确认等级，选择期间KEY2改变候选；长按KEY3约2秒进入三级。解除后台不清除本地记录，解除本地后仍可能显示保留的后台事件。')
para('32位相位累加器以相位最高位输出正负幅度方波PCM，频率近似Δphase×Fs/2^32。二级加入间歇包络，三级切换频率；左右声道复用样本。音频实际采样率约48.028 kHz，为名义48 kHz配置，约0.058%偏差。')
para('emergency_audio_frame_gate检查模式、加载完成、目标缓存和实际读缓存标签。在匹配应急帧的首个有效像素处允许报警，解除时关闭使能。门控对齐的是FPGA内部事件，不宣称显示器与扬声器物理零时间差。')
heading('2.6 可选串口发布')
para('USB-UART使用115200、8N1、无流控。TEXT更新普通通知，PUBLISH录入编号、等级、区域与正文；区域1至16字符、正文1至64字符。电脑工具只编码字形与CRC，不生成图像，FPGA保存、检错、仲裁及渲染。')
para('事件按EBEGIN、ECHAR、ECOMMIT传输。CRC16采用CCITT-FALSE，初值0xFFFF、多项式0x1021、不反射、最终异或0。数量、长度及校验均通过后才提交，并在帧边界共同安装内容和等级。')
para('同编号同内容返回DUP，同编号不同内容报错；CLEAR只清除后台。ESTATUS区分待显示、已输出及本地覆盖，APPLIED仅说明FPGA已输出对应事件帧。串口断开不自动解除已发布事件；复位后动态内容清零。')
page('3 模块接口')
heading('3.1 顶层模块')
para('顶层top位于src/user_source/hdl_source/top_tf_hdmi_audio.v，工程为src/td_project/anshibo.al。表1按当前源码列出外部端口；KEY编号指板上标识，与RTL名称不同。')
table(['信号','位宽','方向','功能'],[
['clk','1','输入','50 MHz板载参考'],['rst_n','1','输入','KEY1复位，低有效'],['key1','1','输入','KEY2，普通模式下一张'],['key2','1','输入','KEY4，自动轮播开关'],['key_mode','1','输入','KEY3，等级选择/确认和长按'],['subtitle_switch','1','输入','SW1，普通文字和波形'],['adjustment_switch','1','输入','SW2，参数调节模式'],['contrast_switch','1','输入','SW3，对比度1/亮度0'],['uart_rx','1','输入','CH340至FPGA，F12'],['uart_tx','1','输出','FPGA至CH340，D12'],['seg_sel','6','输出','数码管片选'],['seg_data','8','输出','数码管段选'],['HDMI_CLK_P','1','输出','HDMI_B TMDS时钟'],['HDMI_D2_P/D1_P/D0_P','各1','输出','HDMI_B三个TMDS数据通道'],['HDMI_DDC_SCL','1','输出','DDC时钟'],['HDMI_DDC_SDA','1','双向','DDC数据'],['sd_ncs','1','输出','TF SPI片选'],['sd_dclk','1','输出','TF SPI时钟'],['sd_mosi','1','输出','TF主发从收'],['sd_miso','1','输入','TF主收从发']], [151,32,42,243])
para('表1 顶层端口。实际引脚和电气配置见src/user_source/constraints_source/pin.adc；SDRAM控制由下层模块与器件绑定资源完成，不在该顶层重复列引脚。','small')
page('3.2 TF与BMP模块')
para('sd_card_bmp协调资源、加载、预读、轮播及缓存提交；当前RESOURCE_ENABLE、PREFETCH_ENABLE、FRAME_READER_FEEDBACK均启用。下表为主要接口，完整端口见SD/sd_card_bmp.v。')
table(['信号','位宽','方向','功能'],[
['clk / rst','各1','输入','100 MHz与高有效复位'],['key_next / key_auto','各1','输入','消抖前普通按键'],['command_valid/code/value','1/4/5','输入','同域控制命令'],['resource_normal_count','5','输出','合法日常BMP数量'],['resource_active_count/index','各5','输出','播放条目数量/当前索引'],['resource_seconds','6','输出','当前画面停留秒数'],['resource_flags','8','输出','资源异常位'],['display_valid','1','输出','首图已提交'],['o_emergency_mode/loaded','各1','输出','应急模式/图片完整提交'],['write_finish_toggle','1','输入','内存整帧写完翻转'],['write_buf_idx/disp_buf_idx','各2','输出','写/显示缓存编号'],['write_req / write_req_ack','各1','输出/输入','写事务请求/应答'],['write_ready','1','输入','FIFO写侧背压'],['write_en / write_data','1/32','输出','像素写使能与数据'],['read_active_index_async','2','输入','实际读端缓存标签'],['transition_pending','1','输出','完整目标可进入转场']], [159,38,53,218])
para('表2 图片控制主要接口。read_slide_mix_async与取消确认等信号保护旧缓存释放，避免相接转场或应急取消时覆盖正在读的数据。','small')
heading('BMP及FAT32子模块')
para('bmp_read的load_start触发加载，ready与load_failed反馈结束和失败；sd_sec_read、sd_sec_read_addr及数据有效/结束组成逻辑扇区读取接口，bmp_data为24位RGB。FAT32模块将逻辑扇区映射到实际簇链，其catalog_ready并不等于无错误，需要同时查看resource_flags。')
page('3.3 HDMI视频与发射模块')
para('视频链路的时序和像素必须匹配。当前输出分辨率固定640×480；修改输入素材不需要改视频PLL，修改输出分辨率则必须同步调整时序、帧长、地址和HDMI配置。')
table(['模块或信号','位宽','方向','说明'],[
['video_timing_data.video_clk/rst','各1','输入','25 MHz与复位'],['read_req / read_req_ack','各1','输出/输入','整帧读取握手'],['hs / vs / de','各1','输出','行同步/场同步/有效区'],['video_rgb_to_axis.I_clk/I_rst','各1','输入','像素时钟与复位'],['I_vs / I_de','各1','输入','对齐后场同步与有效'],['I_rgb','24','输入','图层合成后RGB'],['O_video_user/valid/last','各1','输出','帧首/有效/行末'],['O_video_data','24','输出','AXI视频流像素']], [171,34,53,210])
para('表3 时序与视频流主要接口。video_rgb_to_axis_640x480和campus_osd是同一源文件中的不同模块，不将两者接口混为一体。','small')
heading('HDMI发射IP与PHY')
table(['接口组','方向','用途'],[['I_pixel_clk / I_rst','输入','视频参考和复位'],['I_axis_s_*','输入','视频流及帧/行标志'],['I_audio_valid / left/right_data','输入','样本有效及24位左右PCM'],['I_acr_valid / cts / n','输入','音频时钟恢复参数'],['I_edid_read_trig','输入','启动EDID读取'],['O_ddc_scl / IO_ddc_sda','输出/双向','DDC交互'],['O_ch0/1/2/clk_tmds_data','输出','10位TMDS通道至PHY']], [217,64,187])
para('表4 发射核接口组。PHY在125 MHz域串行化；当前音频接口有效连接，未沿用纯视频例程中的音频置零配置。','small')
page('3.4 FIFO与SDRAM模块')
para('frame_read_write封装读写FIFO与SDRAM用户事务，默认MEM_DATA_BITS=32、ADDR_BITS=21。读写在时钟域间缓冲，存储访问由控制器仲裁；不能把两个逻辑通路并行理解为SDRAM同一时刻双端口访问。')
table(['接口组','方向','用途'],[['mem_clk / Sdr_init_done / Sdr_busy','输入','内存时钟、初始化与忙状态'],['read_clk/read_req/read_len','输入','视频侧读取请求及帧长'],['read_req_ack/read_data','输出','读请求应答与32位数据'],['read_addr_index / write_addr_index','输入','两帧地址区域选择'],['read_active_index / read_slide_mix','输出','实际读帧及混读反馈'],['slide_offset / slide_target_index','输入','水平偏移及新图缓存'],['write_clk/write_req/write_en/write_data','输入','TF侧写入事务'],['write_req_ack/write_finish/write_ready','输出','应答、完整写入与背压'],['App_rd_en/addr  App_wr_en/addr/din','输出','SDRAM用户读写接口']], [236,54,178])
para('表5 内存与FIFO接口组，完整位宽见SD/frame_read_write.v。SDRAM沿用官方控制及加密模块，当前用户接口约41.667 MHz。')
heading('3.5 音频与应急门控模块')
table(['模块','主要输入','主要输出'],[['hdmi_audio_tone_i2s_64fs','I_mclk、I_rst、I_enable、I_alert_level','I2S BCLK/LRCK/DOUT'],['I2S_receiver','I_clk、I_rst、I_i2s_*','valid及24位左右PCM'],['audio_arc_calculate','I_clk、I_rst、I_audio_valid','valid、20位CTS/N'],['emergency_audio_frame_gate','vs/de、模式、加载及缓存标签','audio_enable、picture_ready、restore_ready']], [160,154,154])
para('表6 音频与显示就绪模块。分级控制由graded_alert_ctrl仲裁；event_packet_buffer处理事件双银行、CRC和提交代次，uart_console负责8N1命令接收与应答。','small')
page('4 实验步骤')
heading('4.1 连接与资源准备')
para('开发板连接下载线与电源；HDMI_B连接显示器或带音频输出的接收设备，音箱接相应音频输出。FAT32 TF卡根目录复制tf_resources中的NORMAL及ALERT，插入板卡。串口为选配，用USB-UART连接电脑。')
para('NORMAL放置NNN.BMP，ALERT放EVAC.BMP。必须是真正RGB24无压缩BMP，不能直接把PNG/JPG改后缀；支持宽1至1280、高1至960。首次验证不放PLAYLIST.TXT，确认正常后再配置。修改素材时断电取卡，安全弹出后重新上电。')
heading('4.2 编译 固化与操作')
para('步骤1  TD 6.2.1打开src/td_project/anshibo.al，选择top及EG4S20BG256，保留随包引脚和时序约束。执行综合、布局布线、时序检查及bit流生成；命令行构建从src/td_project运行../../tools/build_td.tcl。')
para('步骤2  BitWriter的PROGRAM_SRAM下载firmware/anshibo_prefetch.bit进行验证。通过后按开发板流程使用PROGRAM_FLASH固化，等待完成再断电；重新上电不执行下载，检查独立启动。')
para('步骤3  等待首图完整提交。KEY2切换下一张，KEY4开启/关闭自动轮播。默认停留5秒，较大文件未预读完可能继续等待；005显示几秒后再切006可观察预加载效果。')
para('步骤4  SW1控制普通字幕波形，SW2进入参数调节，SW3选择对比度或亮度。KEY3选择/确认预警等级，选择中KEY2改变候选，长按KEY3约2秒进入三级；解除后恢复日常。')
para('步骤5  可选运行tools/launch_uart.cmd并输入COM编号。依次测试PING、RESOURCES、TEXT 请到操场集合、TRANSITION FADE/CUT/SLIDE。PUBLISH录入新编号、等级、区域和正文；ESTATUS查询，CLEAR解除后台。每条等待回复，OK只表示受理。')
para('复位或断电后普通字幕、事件与远程设置不保留；无需连接电脑即可完成核心现场演示。','small')
page('4.3 功能测试与实现结果')
table(['项目','检查要点'],[['独立启动','Flash固化后断电重启，不执行下载'],['日常展示','手动、自动、首尾循环及目录新增图片'],['五项拓展','字幕图层、三种转场、缩放、参数OSD、PCM波形'],['预读与应急','预读中触发、无普通帧闪出、直接切屏与恢复'],['后台更新','TEXT与PUBLISH正确，本地同级或更高优先'],['异常与稳定','缺图降级、重复操作、持续轮播无卡死或花屏']], [120,348])
para('表7 最终上板检查项目。当前预加载版本及串口功能由用户反馈运行正常；仿真覆盖BMP像素、FAT32簇链、读帧释放、事件事务和应急帧门控。未记录最终固化重启次数、连续运行小时数及物理端到端延迟。')
heading('编译资源与时序')
table(['资源','结果'],[['LUT / 寄存器','15008/19600  8294/19600'],['BRAM / DSP','60/64  7/29'],['建立时间余量 SWNS','+0.108 ns'],['保持时间余量 HWNS','+0.003 ns'],['STA覆盖率','99.94%']], [188,280])
para('表8 2026年10月8日提交源码重新编译结果。建立与保持检查通过；官方加密模块、时钟布线等仍有警告，不将编译成功解释为所有外部接口约束完整。')
heading('仿真量化边界')
para('25 MHz实际视频时序下，5种注入相位的缓存提交至可启动帧首像素等待约1.41至14.21 ms，报警使能与该像素判定在同一仿真时刻。该结果只针对内部帧门控，不代表终端物理音画差。模型强制的卡初始化和人工读写时延不用于真实启动时间宣传。')
page('4.4 异常检查与交付说明')
table(['现象','检查方法'],[['没有图片','确认HDMI_B、FAT32、资源目录、RGB24及有效尺寸，查询RESOURCES'],['日常没有声音','普通模式为静音；触发二/三级再检查音频设置和音量'],['中文无法发送','仅支持随包607字形；不支持字符不改变当前内容'],['后台清除后仍预警','检查本地等级，CLEAR不清除本地'],['切换大图仍有等待','检查目标是否完成预读；预读不提高TF带宽'],['误认为显示日期','当前是运行时长，不含RTC日期'],['改TF图片未生效','断电更换后重新上电，使用列表时增加对应条目']], [140,328])
para('表9 常见现象与排查。无应急底图时用内置背景和应急文字降级，不据图片缺失推测实际疏散路线。')
heading('交付与来源')
para('源码目录含src、tb、sim、tools、tf_resources、assets、firmware和measurements；SOURCE_GUIDE.md说明模块，SOURCE_ORIGIN.md说明官方模块、IP及扩展，SHA256SUMS.txt提供校验。GitHub仓库为https://github.com/Fish354xx/anshibo-fpga，当前分支event-publish。')
para('SPI、SDRAM、HDMI基础模块及部分IP沿用官方参考，资源管理、图像处理、图层、转场、缓存调度和分级事件为项目实现与扩展，开发中使用AI辅助。文档接口按当前源文件核对，不把旧例程功能或参数视为当前实现。')
heading('限制与改进方向')
para('当前不支持视频解码、联网、全中文字库、RTC日期、事件持久化或语音播报。BRAM已使用93.75%，进一步扩展应控制存储。可增加应急专用缓存或可安全中断的写事务，降低预读对紧急响应的影响；优化缩放滤波并补充物理音画测量。')
para('参考：安路选题指南选题一1.3至1.5；HX4S20C官方手册及HDMI IP文档；项目源码及measurements中的资源、预读、事件和时序验证记录。','small')
def footer(canvas,doc):
 canvas.setFont('CN',8);canvas.setFillColor(colors.HexColor('#666666'));canvas.drawString(54,letter[1]-30,'安视播  技术报告');canvas.drawRightString(letter[0]-54,30,str(doc.page))
path=OUT/'安视播技术报告.pdf'
doc=SimpleDocTemplate(str(path),pagesize=letter,rightMargin=56.7,leftMargin=56.7,topMargin=56.7,bottomMargin=56.7,title='安视播技术报告',author='',subject='校园电子广告牌兼容应急信息发布系统')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
(OUT/'安视播技术报告正文.md').write_text('\n'.join(md),encoding='utf-8')
print(path)
