"""Generate deterministic BMP test cards for FPGA resolution adaptation."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
folder=root/'assets'/'phase8_scaling_test'
folder.mkdir(parents=True,exist_ok=True)
cards=[('00_welcome_320x240.bmp',320,240,'安视播',(25,90,135)),
       ('01_notice_1280x960.bmp',1280,960,'校园公告',(35,110,75)),
       ('02_safety_641x481.bmp',641,481,'安全提醒',(145,100,20)),
       ('03_emergency_640x480.bmp',640,480,'应急提示',(155,30,35))]
for name,w,h,title,color in cards:
    img=Image.new('RGB',(w,h),color);draw=ImageDraw.Draw(img)
    thick=max(2,w//100)
    draw.rectangle((0,0,w-1,h-1),outline='white',width=thick)
    for i in range(1,8):
        draw.line((w*i//8,0,w*i//8,h),fill=tuple(min(255,c+35) for c in color),width=1)
    for j in range(1,6):
        draw.line((0,h*j//6,w,h*j//6),fill=tuple(min(255,c+35) for c in color),width=1)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',max(16,w//13))
    draw.text((w//2,h*3//8),title,font=font,fill='white',anchor='mm')
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',max(12,w//25))
    draw.text((w//2,h*5//8),f'{w} x {h}  ->  640 x 480',font=small,fill='white',anchor='mm')
    draw.text((w//2,h*3//4),'RGB24 BMP / FPGA Scaling',font=small,fill='white',anchor='mm')
    for x,y,c in [(0,0,'red'),(w-1,0,'green'),(0,h-1,'blue'),(w-1,h-1,'yellow')]:
        r=max(4,w//40);draw.rectangle((max(0,x-r),max(0,y-r),min(w-1,x+r),min(h-1,y+r)),fill=c)
    img.save(folder/name,'BMP')
    print(name)
