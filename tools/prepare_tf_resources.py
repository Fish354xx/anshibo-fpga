"""Create a local TF copy package from the project's existing images."""
from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
destination = root / 'tf_resources'
normal = destination / 'NORMAL'
alert = destination / 'ALERT'
normal.mkdir(parents=True, exist_ok=True)
alert.mkdir(parents=True, exist_ok=True)
for source, target in [('00_course.bmp', '001.BMP'), ('01_notice.bmp', '002.BMP'), ('02_lab.bmp', '003.BMP')]:
    shutil.copyfile(root / 'images' / source, normal / target)
shutil.copyfile(root / 'images/03_emergency.bmp', alert / 'EVAC.BMP')
image = Image.new('RGB', (640, 480), '#102438')
draw = ImageDraw.Draw(image)
font_path = 'C:/Windows/Fonts/msyh.ttc'
title = ImageFont.truetype(font_path, 36)
body = ImageFont.truetype(font_path, 23)
draw.rounded_rectangle((28, 28, 612, 452), radius=20, outline='#4ccbc6', width=3)
draw.text((74, 110), '新增日常资源测试', font=title, fill='white')
for y, text in [(190, '图片编号：004.BMP'), (238, '日常资源与应急资源分开管理'), (286, '此图片用于验证第四张日常图片'), (334, '串口输入 RESOURCES 查看资源状态')]:
    draw.text((54, y), text, font=body, fill='#bce8ed')
image.save(normal / '004.BMP')
(destination / 'PLAYLIST.TXT').write_bytes(b'# File,seconds\r\n001.BMP,5\r\n002.BMP,5\r\n003.BMP,5\r\n004.BMP,5\r\n')
for path in list(normal.glob('*.BMP')) + list(alert.glob('*.BMP')):
    data = path.read_bytes()
    if data[:2] != b'BM' or int.from_bytes(data[28:30], 'little') != 24 or int.from_bytes(data[30:34], 'little') != 0:
        raise ValueError(f'Unexpected image format: {path}')
print(f'Prepared local copy package: {destination}; four daily BMPs and independent emergency BMP')
