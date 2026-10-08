from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'submission/technical_document'
OUT.mkdir(parents=True,exist_ok=True)
pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/simhei.ttf'))
styles={
 'title':ParagraphStyle('title',fontName='CN',fontSize=23,leading=31,spaceAfter=13,textColor=colors.black),
 'h1':ParagraphStyle('h1',fontName='CN',fontSize=17,leading=24,spaceAfter=12,textColor=colors.black),
 'h2':ParagraphStyle('h2',fontName='CN',fontSize=12,leading=18,spaceBefore=10,spaceAfter=5,textColor=colors.black),
 'body':ParagraphStyle('body',fontName='CN',fontSize=10.5,leading=17,spaceAfter=8,wordWrap='CJK'),
 'cell':ParagraphStyle('cell',fontName='CN',fontSize=9,leading=13,wordWrap='CJK'),
 'small':ParagraphStyle('small',fontName='CN',fontSize=8.5,leading=13,spaceAfter=6,wordWrap='CJK')}
story=[];md=[]
def para(t,kind='body'):
 story.append(Paragraph(escape(t).replace('\n','<br/>'),styles[kind]));md.append(t+'\n')
def heading(t):para(t,'h2')
def page(t):
 if story:story.append(PageBreak())
 para(t,'h1');md.append('---\n')
def table(headers,rows,widths):
 data=[[Paragraph(escape(str(v)),styles['cell']) for v in row] for row in [headers]+rows]
 t=Table(data,colWidths=widths,repeatRows=1,hAlign='LEFT')
 t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#E7EDF2')),('GRID',(0,0),(-1,-1),.5,colors.HexColor('#D9D9D9')),('VALIGN',(0,0),(-1,-1),'MIDDLE'),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8)]))
 story.extend([t,Spacer(1,9)])
 md.extend([' | '.join(map(str,row))+'\n' for row in [headers]+rows])
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
para('校园电子广告牌兼容应急信息发布系统技术报告','h1')
para('2026年全国大学生嵌入式芯片与系统设计竞赛 FPGA赛道 安路科技选题一','small')
heading('摘要')
para('安视播以HX4S20C开发板上的EG4S20BG256 FPGA为核心，将校园海报展示、滚动通知和分级应急发布统一到HDMI显示终端。FPGA读取TF卡中的FAT32目录及BMP资源，完成最近邻缩放、SDRAM双缓冲管理、下一张预加载、图片转场、参数处理与文字波形叠加，并生成分级提示音。日常资源与应急底图独立管理，便于维护；应急进入和解除绕过动画，在缓存完整且读通路就绪后切换。')
para('板载按键与拨码可独立操作全部核心展示功能。额外串口管理支持普通字幕更新和包含事件编号、等级、区域、正文的事务式发布。图像、图层、缓存、音频及等级仲裁均在FPGA中实现，不使用额外处理器生成展示画面。')
heading('应用目标')
para('面向教学楼走廊、公共大厅及实验室入口，常态轮播课程占用、校园活动和实验室注意事项；提醒或演练时发布分级信息；紧急状态显示预设疏散底图与文字，并播放报警。系统为信息发布演示原型，不承担火情检测、消防联动认证或现场路线自动规划。')
heading('关键词')
para('FPGA信息发布  双缓冲图像展示  分级应急音画联动')
table(['项目','当前配置'],[['核心平台','HX4S20C  EG4S20BG256'],['图像与显示','RGB24无压缩BMP  HDMI 640×480'],['资源组织','NORMAL日常目录  ALERT/EVAC.BMP应急底图'],['开发与交付','TD 6.2.1  Verilog HDL  可固化启动']], [105,363])
para('报告对应2026年10月8日整理的最终源码及已确认正常的预加载固件。','small')
page('1 系统结构与运行逻辑')
para('系统按资源读取、缓存控制、像素输出及交互管理分工。读取端可在显示当前帧的同时准备下一帧；视频端按固定行场时序取像素，叠加模块逐像素处理，音频端持续发送I2S样本。不同时间域通过FIFO、两级同步和请求确认握手衔接。')
diagram()
heading('日常与应急状态')
para('日常状态按编号或播放列表轮播图片，允许手动切换、字幕更新及参数调节。一级提醒保留日常播放并增加提示；二级进入警戒页面并输出间歇提示音；三级使用独立应急底图、区域及正文，输出交替报警。解除后恢复日常资源和普通字幕。')
para('本地与后台各保存一个预警等级，取较高等级作为实际输出，同级本地优先。后台清除不清除本地记录。应急切屏仍需等待完整缓存和显示边界，不将“无动画”解释为零加载延迟。')
table(['时钟域','用途'],[['50 MHz输入','板载时钟输入与PLL参考'],['100 MHz','TF资源、BMP及控制逻辑'],['约41.667 MHz','SDRAM缓存访问'],['25 MHz与125 MHz','像素处理及HDMI串行发送'],['约12.295082 MHz','音频主时钟与I2S样本发送']], [132,336])
para('640×480有效区采用800×525总时序，单帧约16.8 ms，刷新率约59.52 Hz。各子域采用异步复位请求与同步释放，避免复位解除跨域。','small')
page('2 TF资源管理与BMP解码')
heading('只读FAT32资源索引')
para('fat32_resources挂载512字节扇区的FAT32卷，支持MBR分区及无分区表卷，检查BPB几何与活动FAT字段。扫描根目录及NORMAL、ALERT目录，沿簇链读取目录和文件，以逻辑扇区映射支持非连续存放的图片。')
para('NORMAL采用000.BMP至999.BMP的短文件名，最多保留16张合法日常图片，默认按编号排序。ALERT/EVAC.BMP不占日常名额，增加日常图片不会改变应急资源定位。修改TF内容后重新上电建立索引，运行中不热插拔或写卡。')
heading('可选播放列表')
para('根目录PLAYLIST.TXT最多512字节、16个有效条目。001.BMP,5表示该图片停留5秒，范围为1至60秒；支持改变顺序、部分选择及重复引用。没有有效列表时使用编号顺序和默认5秒。停留时间与加载、动画时间不是同一个指标。')
heading('BMP检查与像素读取')
para('检查BMP标识、数据偏移、位深、压缩方式及尺寸，仅接收正高度的24位RGB无压缩格式，宽1至1280、高1至960。按BMP的BGR字节顺序组装像素，每行步长按4字节对齐；正高度BMP的自底向上排列由写入地址转换为正确显示方向。')
para('行字节数 = 4 × ceil(3 × 图片宽度 / 4)。BMP头合法后才进入资源索引，整帧数据完整且内存写入完成后才允许提交显示。输出节拍限速与写通路就绪共同约束像素发送，避免FIFO吞吐失配。')
heading('异常降级')
para('非法图片头不加入索引；无日常图片时显示内置背景和资源提示；应急底图缺失时仍保留应急文字与音频。运行时坏簇、越界或提前结束使资源失效，排空当前事务后降级，不把损坏缓存作为正常画面提交。目录扫描设上限，不宣称修复任意损坏文件系统。')
para('资源状态查询提供有效文件数、播放条目数、应急文件存在状态及错误位，便于定位TF格式与素材问题。','small')
page('3 图片缩放与双缓冲预加载')
heading('最近邻缩放')
para('目标输出固定为640×480。对于输出坐标(x,y)，选择源像素xs=floor(x×W/640)，ys=floor(y×H/480)，其中W、H为源图尺寸。流式缩放器采用坐标累加与行缓存完成采样、丢弃或重复，不保存完整源图到片内RAM。')
para('这种方法计算与存储成本较低，适合有限逻辑和BRAM资源；放大时存在像素块状感，缩小时没有抗混叠滤波。非4:3素材当前直接拉伸适配，不提供等比例留黑边或双线性插值。')
heading('两帧缓存与完整性条件')
para('每帧307200个32位字，包含RGB24及填充字节；两帧共2457600字节。当前帧由显示端读取，备用帧由加载端写入。提交条件同时检查源处理结束与SDRAM整帧写入完成，缓存编号、图片索引、停留时间及异常背景标记一并更新。')
heading('后台预读与缓存命中')
para('当前普通图片稳定显示后，在没有混合读取旧新帧且备用缓存可写时，加载顺序上的下一张。预读完成不会主动换图。手动下一张或轮播到期命中该缓存时，直接启动转场，不再次读TF或重写像素。任意指定图片未命中时沿常规读取路径加载。')
para('停留计时可与预读并行。到期时目标未完成，保留请求并继续显示旧图，完成后再处理。关闭轮播后可保留下一张缓存。相接转场期间两帧仍在读取，必须收到读端采用与释放反馈，才可覆盖旧帧。')
heading('应急期间的调度边界')
para('应急优先于普通请求；已完成的日常预读缓存作废，正在写入的预读事务先安全排空，再加载应急资源。该策略保护缓存一致性，但应急可能多等待剩余预读时间。预加载隐藏日常读取等待，不提高SPI带宽，也不保证立即切换大图。')
para('本版复用原有双缓冲，无额外应急专用帧缓存；已通过预读中应急抢占、普通帧不误提交、恢复重建缓存及失败降级的仿真检查。','small')
page('4 转场与图层处理算法')
heading('相接滑动转场')
para('默认SLIDE令旧图向左移动，新图从右紧接进入。设水平偏移d，x＜640-d时读取旧图的x+d位置，否则读取新图的x-(640-d)位置。两段同一行拼接覆盖全部640像素，中间不插入黑色画面。')
para('frame_fifo_read在每帧锁存缓存及偏移，分段生成读地址。picture_transition每帧推进40像素，16步完成，按当前时序运动约268.8 ms；实际请求到完成还受加载和读缓存采用影响。FADE采用淡出后淡入，CUT直接提交；应急进入和解除旁路动画。')
heading('亮度与对比度')
para('每个颜色通道执行Cout=clamp(g×(Cin-128)+128+b,0,255)。五档对比度增益为0.5、0.75、1、1.25、1.5；五档亮度偏移为-64、-32、0、32、64。使用移位、加法及饱和裁剪实现，默认档位均为2。')
heading('字幕及图层优先级')
para('普通通知采用字形ROM和字幕缓存，根据屏幕坐标查字模并生成前景像素。滚动偏移随显示帧推进；上传写备用银行，帧边界整体提交，避免一条字幕的新旧内容混杂。当前支持607个字形，包括95个ASCII字符与512个汉字及中文标点，普通字幕最多64字符。')
para('图片先进行参数处理，再合成状态、时间、字幕、预警和波形信息。普通SW1开关控制文字与波形；资源异常和应急信息按安全提示逻辑呈现。显示时间为复位后的运行时长，开发板未配置实时时钟。')
heading('音频波形')
para('从音频PCM样本提取有符号幅度，保存到波形缓存并以帧快照映射到屏幕坐标，绘制波形。可视化对应系统内部音源，日常静音时波形接近基线；没有麦克风采集、外部音乐分析或FFT频谱。')
page('5 分级应急与HDMI音频联动')
table(['等级','显示与控制','声音'],[['一级提醒','提示信息叠加，日常播放继续','静音'],['二级警戒','警戒页、区域及正文，直接切屏','约880 Hz间歇提示'],['三级应急','EVAC底图与疏散信息，直接切屏','约660/880 Hz交替报警']], [65,275,128])
heading('本地操作与优先级')
para('KEY3用于预警等级选择和确认，选择期间KEY2切换候选等级；长按KEY3约2秒进入三级。KEY2、KEY4在正常模式分别执行下一张和轮播开关。SW2开启参数调节，SW3选择对比度或亮度，SW1控制普通字幕与波形。')
para('本地与后台等级分开保存，仲裁取最大等级，同级选择本地。完整后台事件即使被本地覆盖也仍可保留，解除本地后根据剩余后台状态输出；CLEAR只清除后台，不能撤销本地应急。')
heading('音源生成与发送')
para('采用32位相位累加器产生提示音：phase_next=phase+Δphase，频率近似为Δphase×Fs/2^32。相位最高位决定正负固定幅度，生成方波PCM；二级增加间歇包络，三级定期切换频率。提示音在FPGA生成，不从TF读取音频文件。')
para('24位PCM左右声道复用，经I2S进入HDMI音频链路。音频主时钟约12.295082 MHz，每立体声帧256个主时钟周期，实际采样率约48.028 kHz，属于名义48 kHz配置，约有0.058%偏差，提示音频率也有对应偏差。')
heading('实际读帧就绪门控')
para('emergency_audio_frame_gate同步应急模式、图片加载完成、目标缓存与实际读缓存标签。只有标签匹配且到达应急帧首个有效像素时，才允许报警；解除时关闭报警使能。避免仅凭加载请求或逻辑模式变化启动声音。')
para('该门控关联FPGA内部的显示与音频启动条件，HDMI传输、采样及显示器和扬声器处理仍会带来延迟，不宣称物理音画零时间差。','small')
page('6 可选后台发布与事件一致性')
para('串口作为额外管理入口，采用115200波特率、8N1及无流控。板载CH340提供USB串口桥接，F12为FPGA接收、D12为发送。核心演示无需电脑；连接电脑时仅输入管理内容和指令，FPGA负责接收、校验、缓存、仲裁及渲染。')
heading('普通通知与完整事件')
para('TEXT更新普通滚动字幕。PUBLISH向导录入事件编号、等级、区域和正文；区域1至16字符，正文1至64字符。电脑端根据随包字形表编码并生成CRC，FPGA核对数量、长度与CRC后才提交。开发阶段生成的字形ROM已包含在源码中。')
para('CRC16采用CCITT-FALSE参数：多项式0x1021，初值0xFFFF，不反射，最终异或值0。校验覆盖编号、等级、字段长度及全部字形。CRC用于传输检错，不提供身份认证或加密。')
heading('事务与帧边界安装')
para('EBEGIN建立备用事务，ECHAR逐字写入，ECOMMIT校验并提交，错误不覆盖当前有效事件。双银行将正在显示的内容与新上传内容分离，等级和正文在帧边界共同安装。内部提交代次避免清除后编号复用继承旧显示回执。')
para('当前有效事件同编号同内容返回DUP；同编号不同内容报错。只保留一个最新后台事件，不保存长期事件队列。ESTATUS区分接受、待输出和本地覆盖，APPLIED表示FPGA已输出对应事件帧，不证明物理终端已完成响应。')
table(['指令','作用'],[['PING  STATUS  RESOURCES','通信、运行及资源状态查询'],['NEXT  SHOW  AUTO','切图、指定播放条目及轮播'],['TEXT  TRANSITION','普通字幕和转场设置'],['PUBLISH  ESTATUS  CLEAR','完整事件发布、状态与后台清除'],['LOCAL  EXIT','交回拨码控制，关闭电脑串口']], [160,308])
para('该附加路径的电脑工具参与文字编号转换与检错编码，因此比赛核心演示以板端独立运行及FPGA数据处理为主；串口扩展是否纳入“不得有额外处理器辅助控制或预处理”的评审范围，应遵循赛事解释。','small')
page('7 验证结果与赛题对应')
heading('实现时序与资源')
para('最终源码文件夹在TD 6.2.1中重新完成综合、布局布线与bit流生成。2026年10月8日报告：SWNS +0.108 ns、HWNS +0.003 ns，时序覆盖率99.94%。建立和保持检查通过；仍存在官方加密模块及布线等警告，不将通过等同于零警告或全部外部接口约束完整。')
table(['资源','用量','占比'],[['LUT','15008 / 19600','76.57%'],['寄存器','8294 / 19600','42.32%'],['BRAM','60 / 64','93.75%'],['DSP','7 / 29','24.14%']], [155,175,138])
heading('功能验证')
para('当前预加载版本上板运行正常，串口功能检查未发现问题。仿真覆盖FAT32解析、BMP缩放、转场读地址、缓存释放、分级事件、字幕事务、应急帧门控和预读调度。预读完整通路测试累计写入9帧，覆盖命中、未命中、应急打断与失败降级。')
para('25 MHz真实视频时序下，5种注入相位的缓存提交至可启动帧首像素等待分别为1.414500、1.413540、14.214540、10.214540及2.214540 ms；报警使能与帧首像素判定在同一仿真时刻。标签采用为模型注入，未测物理显示器或音响延迟，不将调度模型中的纳秒启动值用于产品性能宣传。')
table(['要求','对应实现','验证依据'],[['核心展示与音频','TF BMP、SDRAM、HDMI、分级音源','上板反馈及仿真'],['图层与字幕','滚动字幕、状态、时间、预警叠加','上板反馈及事务测试'],['轮播与转场','手动/自动、SLIDE/FADE/CUT','上板反馈及拼接测试'],['缩放适配','不同尺寸BMP、最近邻采样','上板反馈及像素测试'],['参数与OSD','五档亮度/对比度、SW控制','上板反馈及控制测试'],['音频可视化','内部PCM波形叠加','上板反馈及波形测试']], [115,218,135])
page('8 工程交付与改进方向')
heading('交付文件及复现')
para('最终源码目录包含src、tb、sim、tools、tf_resources、assets、firmware及measurements。TD打开src/td_project/anshibo.al，顶层top，器件EG4S20BG256。工程40项文件依赖均存在，头文件检查未发现缺失，SHA256SUMS.txt提供逐文件校验。')
para('当前固件为firmware/anshibo_prefetch.bit。PROGRAM_SRAM用于临时验证，PROGRAM_FLASH用于固化；固化后必须断电重新上电检查独立启动。已完成运行功能检查；最终Flash断电启动和物理响应时间未纳入本次量化记录。')
para('GitHub仓库：https://github.com/Fish354xx/anshibo-fpga 。当前开发分支event-publish，整理及重编译检查提交2a71e21。源码导出基于3c7892c，之后追加检查记录，不改变产品RTL逻辑。')
heading('来源与开发范围')
para('工程保留安路官方SPI、SDRAM、HDMI参考模块及PLL/FIFO工具生成IP、加密IP；SOURCE_ORIGIN.md记录来源。项目实现和扩展包括资源管理、缩放、图层、缓存调度、转场、分级仲裁、事件事务和音画门控，开发过程中使用AI辅助。')
heading('当前限制与后续优化')
para('BRAM利用率93.75%，新增功能需控制片内存储。最近邻缩放缺乏抗混叠，字库范围有限，动态通知及后台事件复位后不保留。FAT32只读，不支持exFAT、长文件名及热更新；未实现视频解码、联网、实时时钟、事件认证或语音播报。')
para('可进一步增加独立应急缓存或可安全中断的加载事务，减少预读对紧急响应的影响；优化缩放滤波；扩充字库；补充逻辑分析仪和光电音频同步实测。上述为后续方向，不计入已完成功能。')
heading('参考与证据索引')
para('1 2026FPGA赛道选题指南 安路科技 选题一1.3至1.5。\n2 安路官方HX4S20C开发板手册、参考工程及HDMI IP文档。\n3 SOURCE_GUIDE.md与SOURCE_ORIGIN.md。\n4 measurements/submission_audit及prefetch 时序资源报告。\n5 measurements/quantitative 仿真CSV及适用边界。\n6 EVENT_PROTOCOL.md、RESOURCE_MANAGEMENT.md、PREFETCH.md。','small')
para('结论：安视播已形成面向校园日常展示和分级应急的信息发布链路，覆盖图层字幕、转场、缩放、参数OSD及波形五项拓展，特色在于资源角色独立、双缓存预读和事件一致性。最终评价仍以比赛现场演示及提交证据为准。')
def footer(canvas,doc):
 canvas.setFont('CN',8);canvas.setFillColor(colors.HexColor('#666666'));canvas.drawString(54,letter[1]-35,'安视播  技术报告');canvas.drawRightString(letter[0]-54,30,str(doc.page))
path=OUT/'安视播技术报告.pdf'
doc=SimpleDocTemplate(str(path),pagesize=letter,rightMargin=54,leftMargin=54,topMargin=55,bottomMargin=48,title='安视播技术报告',author='',subject='校园电子广告牌兼容应急信息发布系统')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
(OUT/'安视播技术报告正文.md').write_text('\n'.join(md),encoding='utf-8')
print(path)
