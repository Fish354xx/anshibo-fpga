from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor,white
from reportlab.lib.pagesizes import A3
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'submission/poster';OUT.mkdir(parents=True,exist_ok=True)
pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/simhei.ttf'))
W,H=A3
c=canvas.Canvas(str(OUT/'安视播作品海报.pdf'),pagesize=A3)
c.setTitle('安视播 通用多媒体信息展示与分级应急发布系统');c.setAuthor('')
navy='#132B43';blue='#1B5E82';teal='#168A8C';gray='#53677B';line='#DAE4EB';light='#F2F6F8';red='#C84645'
def rect(x,y,w,h,color,round=0):
 c.setFillColor(HexColor(color));c.setStrokeColor(HexColor(color))
 if round:c.roundRect(x,y,w,h,round,stroke=0,fill=1)
 else:c.rect(x,y,w,h,stroke=0,fill=1)
def text(x,y,t,size=14,color=navy):
 c.setFillColor(HexColor(color));c.setFont('CN',size);c.drawString(x,y,t)
def center(x,y,t,size=14,color=navy):
 c.setFillColor(HexColor(color));c.setFont('CN',size);c.drawCentredString(x,y,t)
def arrow(x1,y1,x2,y2,color=teal):
 c.setStrokeColor(HexColor(color));c.setLineWidth(1.8);c.line(x1,y1,x2,y2)
 c.setFillColor(HexColor(color));p=c.beginPath();p.moveTo(x2,y2);p.lineTo(x2-7,y2+4);p.lineTo(x2-7,y2-4);p.close();c.drawPath(p,stroke=0,fill=1)
def label(y,n,title):
 rect(42,y-5,30,27,teal,4);center(57,y+2,n,14,'#FFFFFF');text(84,y,title,22)
def lines(x,y,arr,size=14,color=gray,leading=22):
 for t in arr:text(x,y,t,size,color);y-=leading
rect(0,0,W,H,'#FFFFFF')
rect(0,H-206,W,206,navy)
rect(42,H-48,126,4,'#49C4BC')
text(42,H-111,'安视播',59,'#FFFFFF')
text(46,H-154,'通用多媒体信息展示与分级应急发布系统',25,'#FFFFFF')
text(46,H-182,'FPGA独立展示  |  日常内容发布  |  分级应急联动',14,'#B6DDE4')
text(42,H-243,'一套展示平台，服务多种信息发布场景',23)
lines(42,H-271,['适用于公共大厅、园区、商业展示与校园；当前以校园场景验证功能。'],14)
# Product UI illustration and emergency hierarchy.
x,y=42,H-501
rect(x,y,454,183,navy,12);rect(x+10,y+12,434,161,'#F0F5F8',5)
rect(x+10,y+139,434,34,blue)
text(x+26,y+152,'安视播  |  日常信息展示',14,'#FFFFFF')
rect(x+26,y+56,243,68,'#DFEBF2',5)
text(x+41,y+99,'活动海报 / 公共通知',21)
text(x+41,y+73,'资源来自TF卡 · 按配置轮播',12,gray)
rect(x+284,y+56,144,68,'#FFFFFF',5)
text(x+295,y+100,'运行状态',13)
text(x+295,y+79,'图片 / 字幕 / 波形',11,gray)
rect(x+26,y+26,402,21,blue,3);text(x+36,y+32,'滚动通知：请保持通道畅通，有序通行',11,'#FFFFFF')
text(x,y-17,'界面功能示意，实际素材与通知可更换',10,gray)
text(529,y+157,'从日常展示到应急提示',18)
for yy,col,title,desc in [(y+117,teal,'一级提醒','提示叠加 · 日常播放继续'),(y+66,'#BF8537','二级警戒','警戒信息 · 间歇提示音'),(y+15,red,'三级应急','应急底图 · 交替报警')]:
 rect(529,yy,7,33,col,2);text(547,yy+20,title,16,col);text(547,yy+1,desc,12,gray)
# Features
fy=H-561
label(fy,'01','完整的展示与交互功能')
rows=[('素材维护','FAT32目录与簇链读取','最多16张日常图，独立应急资源及可选播放列表'),('图像展示','缩放适配与三种转场','最近邻缩放，SLIDE相接滑动 / FADE / CUT'),('实时交互','文字图层与画面调节','滚动字幕、运行时间、亮度 / 对比度、PCM波形'),('应急发布','本地优先与事件一致性','分级仲裁，应急直接切屏，缓存就绪后联动报警')]
for i,(a,b,d) in enumerate(rows):
 yy=fy-38-i*49
 if i%2==0:rect(42,yy-17,W-84,46,light,4)
 text(56,yy+5,a,14,teal);text(160,yy+5,b,16)
 text(160,yy-12,d,12,gray)
# Pipeline
py=fy-261
label(py,'02','核心逻辑在FPGA内实现')
bw=133;by=py-81
stages=[('TF资源','FAT32 / BMP'),('图像适配','最近邻缩放'),('双帧缓存','SDRAM / 预读'),('像素处理','转场 / 图层'),('音视频输出','HDMI / PCM')]
for i,(a,b) in enumerate(stages):
 xx=42+i*151
 rect(xx,by,bw,52,light,5);center(xx+bw/2,by+31,a,16);center(xx+bw/2,by+12,b,11,gray)
 if i<4:arrow(xx+bw+2,by+26,xx+149,by+26)
lines(42,by-27,['显示当前帧的同时准备下一帧；完整写入、读端释放与帧边界握手保护缓存一致性。','预加载减少日常切换等待；应急进入与解除绕过动画。'],13,gray,21)
# Advantage and quantitative engineering evidence
ay=by-109
label(ay,'03','可维护 可验证 可独立运行')
lines(42,ay-32,['更换素材无需改RTL；可选串口实时更新字幕及完整预警事件。','Flash固化后独立运行；图像解析、渲染、仲裁与音频生成由FPGA完成。'],13,gray,21)
rect(42,ay-121,W-84,46,light,5)
for xx,a,b in [(60,'HX4S20C','EG4S20BG256'),(273,'640×480','HDMI显示输出'),(478,'双缓冲预读','复用两帧SDRAM'),(659,'时序通过','建立与保持检查')]:
 text(xx,ay-94,a,16);text(xx,ay-111,b,10,gray)
# Footer
c.setStrokeColor(HexColor(line));c.setLineWidth(1);c.line(42,46,W-42,46)
text(42,26,'展示终端原型 · 校园为当前验证场景 · 资源与通知可按场景配置',10,gray)
text(W-175,26,'安路FPGA选题一',10,gray)
c.save()
print('PDF created')
