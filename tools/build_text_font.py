"""Build the fixed 16x16 subtitle ROM and host character index together.

Run once during engineering. Runtime terminal only maps characters to IDs;
FPGA stores, scrolls and renders all subtitle pixels.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
words = '''今天下午点在教学楼举行消防演练请同学们有序离开教室前往操场集合注意安全校园通知实验室课程安排当日占用应急疏散保持冷静禁止乘坐电梯沿绿色出口指示方向撤离听从老师工作人员指挥勿拥挤推搡返回取物祝大家学习愉快文明同行信息发布欢迎使用安视播系统计算机电子工程学院数学英语物理化学生物历史地理音乐体育美术政治选修必修一二三四五六七八九十百千万零年月份周星期时分秒上午中午晚上早自习晚自习会议培训讲座活动考试开始结束调课停课补课地点时间联系电话负责人值班号栋层间门窗桌椅照明空调水源电源设备仪器仪表操作规程先检查再启动关机断电清洁卫生借还登记佩戴护目镜手套口罩不得饮食吸烟携带危险品湿手触碰插座发现异常立即报告维修故障处理热高压低温锋利易燃爆炸毒性腐蚀防护措施垃圾分类节约资源爱护公共财物图书馆食堂宿舍走廊大厅入口出口右左直转弯紧急救援急救电话报警火警火灾地震洪水雷雨恶劣天气避险逃生绿色通道车辆道路交通通行慢速谨慎礼让行人预约签到公告通知提醒重要最新暂停恢复正常状态远程本地自动手动亮度对比字幕波形显示隐藏参数播放图片声音测试联网连接通信成功失败更新内容确认取消重置保存上传下载校区南北东西中央编号总人数容量剩余空闲满员开放关闭仅限授权未经许可严禁擅自拆卸移动更改设置数据文件备份保护个人隐私账号密码网络不要共享陌生链接诈骗警惕健康体检心理咨询疫情传染洗手消毒保持距离爱惜粮食宿舍管理熄灯时间门禁登记访客教师学生管理员值日责任支持服务帮助反馈意见建议公告栏失物招领寻找领取奖比赛报名截止日期成绩公布寒暑假放假返校报到毕业迎新志愿者社团招聘实践创新创业科研项目答辩展示评审专家组提交材料设计文档源代码视频现场演示中华人民共和国家国庆劳动儿童青年元旦春节中秋端午清明重阳祝贺节日快乐，。：；！？（）【】、－＋％／'''
extra_labels=json.loads((root/'design/alert_labels.json').read_text(encoding='utf-8'))
characters = list(dict.fromkeys([chr(i) for i in range(32, 127)] + list(words) + list(''.join(extra_labels.values()))))
if len(characters) > 1024:
    raise ValueError(f'Font capacity exceeded: {len(characters)}')
font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf', 16)
lines = ['// Generated fixed font: IDs agree with tools/text_font.json.',
         'reg [15:0] dynamic_font_rom [0:16383];', 'initial begin']
for index in range(1024):
    canvas = Image.new('1', (16,16))
    if index < len(characters):
        draw = ImageDraw.Draw(canvas)
        char = characters[index]
        bbox = draw.textbbox((0,0), char, font=font)
        draw.text(((16-(bbox[2]-bbox[0]))//2-bbox[0],
                   (16-(bbox[3]-bbox[1]))//2-bbox[1]), char, font=font, fill=1)
    for y in range(16):
        bits = sum(int(canvas.getpixel((x,y))) << (15-x) for x in range(16))
        lines.append(f"dynamic_font_rom[{index*16+y}]=16'h{bits:04X};")
lines.append('end')
target = root/'src/user_source/hdl_source/video_rgb_to_axis_640x480.v'
source = target.read_text(encoding='utf-8-sig')
start, end = '// DYNAMIC_FONT_BEGIN', '// DYNAMIC_FONT_END'
block = start+'\n'+'\n'.join(lines)+'\n'+end
if start in source:
    source = source[:source.index(start)] + block + source[source.index(end)+len(end):]
else:
    source = source.replace('reg [15:0] glyph_rom [0:1023];',
                            block+'\nreg [15:0] glyph_rom [0:1023];')
target.write_text(source, encoding='utf-8')
(root/'tools/text_font.json').write_text(json.dumps(
    [{"character":c,"id":i} for i,c in enumerate(characters)], ensure_ascii=False, indent=2), encoding='utf-8')
(root/'tools/SUPPORTED_TEXT.txt').write_text(''.join(characters),encoding='utf-8')
print(f'Font characters: {len(characters)}; Chinese/punctuation: {len(characters)-95}')


