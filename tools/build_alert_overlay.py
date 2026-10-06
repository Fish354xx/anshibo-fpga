"""Generate fixed graded-alert labels, sharing the runtime subtitle font."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
labels={
 'reminder':'一级提醒：请关注校园通知',
 'warning_title':'二级警戒', 'critical_title':'三级紧急',
 'warning_action1':'请暂停当前活动', 'warning_action2':'听从现场工作人员指引',
 'warning_action3':'注意通行安全',
 'critical_action':'请按疏散指引有序离开',
 'warning_ticker':'二级警戒  请暂停当前活动，听从现场工作人员指引  ',
 'critical_ticker':'三级紧急  请保持冷静，按疏散指引有序离开，禁止乘坐电梯  ',
 'select0':'待确认：解除本地预警', 'select1':'待确认：一级提醒',
 'select2':'待确认：二级警戒', 'select3':'待确认：三级紧急',
 'help':'KEY2选择  KEY3确认'}
(root/'design/alert_labels.json').write_text(json.dumps(labels,ensure_ascii=False,indent=2),encoding='utf-8')
p=root/'tools/build_text_font.py';s=p.read_text(encoding='utf-8-sig')
s=s.replace("characters = list(dict.fromkeys([chr(i) for i in range(32, 127)] + list(words)))",
 "extra_labels=json.loads((root/'design/alert_labels.json').read_text(encoding='utf-8'))\ncharacters = list(dict.fromkeys([chr(i) for i in range(32, 127)] + list(words) + list(''.join(extra_labels.values()))))")
p.write_text(s,encoding='utf-8');exec(compile(s,str(p),'exec'),{'__file__':str(p)})
mapping={e['character']:e['id'] for e in json.loads((root/'tools/text_font.json').read_text(encoding='utf-8'))}
lines=['module alert_overlay_layout(input [9:0]x,y,scroll,input[1:0]level,candidate,',
 'input selecting,output reg band,text,output reg[9:0]glyph,output reg[3:0]row,col,',
 'output reg[23:0]background,ink);']
for key,text in labels.items():
 lines += [f'function[9:0]{key};input[5:0]i;begin case(i)']
 lines += [f"{i}:{key}=10'd{mapping[c]};" for i,c in enumerate(text)]
 lines += [f'default:{key}=0;endcase end endfunction']
lines += ['wire[9:0]tx=x+scroll;', 'always @(*)begin',
 "band=0;text=0;glyph=0;row=0;col=0;background=24'hFFC040;ink=24'h182838;",
 'if(level==1&&y>=416&&y<440)begin band=1;',
 'if(y>=420&&y<436&&x>=16)begin text=1;row=y-420;col=(x-16)&15;glyph=reminder((x-16)>>4);end end',
 "if(level==2)begin band=1;background=24'h182838;ink=24'hFFF4D0;",
 'if(x>=96&&y>=96&&y<128)begin text=1;row=(y-96)>>1;col=((x-96)>>1)&15;glyph=warning_title((x-96)>>5);end',
 'if(x>=96&&y>=180&&y<196)begin text=1;row=y-180;col=(x-96)&15;glyph=warning_action1((x-96)>>4);end',
 'if(x>=96&&y>=224&&y<240)begin text=1;row=y-224;col=(x-96)&15;glyph=warning_action2((x-96)>>4);end',
 'if(x>=96&&y>=268&&y<284)begin text=1;row=y-268;col=(x-96)&15;glyph=warning_action3((x-96)>>4);end',
 "if(y>=80&&y<144)begin background=24'hFFC040;ink=24'h182838;end end",
 "if(level==3&&y>=80&&y<144)begin band=1;background=24'hBA2028;ink=24'hFFFFFF;",
 'if(x>=96&&y>=96&&y<128)begin text=1;row=(y-96)>>1;col=((x-96)>>1)&15;glyph=critical_title((x-96)>>5);end end',
 "if(level==3&&y>=156&&y<188)begin band=1;background=24'h182838;ink=24'hFFFFFF;",
 'if(x>=96&&y>=164&&y<180)begin text=1;row=y-164;col=(x-96)&15;glyph=critical_action((x-96)>>4);end end',
 "if(level>=2&&y>=440&&y<472)begin band=1;background=(level==3)?24'hBA2028:24'hFFC040;ink=(level==3)?24'hFFFFFF:24'h182838;",
 'if(y>=448&&y<464)begin text=1;row=y-448;col=tx[3:0];glyph=(level==3)?critical_ticker(tx[9:4]):warning_ticker(tx[9:4]);end end',
 "if(selecting&&y>=368&&y<416)begin band=1;background=24'h133C68;ink=24'hFFFFFF;text=0;",
 'if(x>=16&&y>=376&&y<392)begin text=1;row=y-376;col=(x-16)&15;case(candidate)',
 '0:glyph=select0((x-16)>>4);1:glyph=select1((x-16)>>4);2:glyph=select2((x-16)>>4);3:glyph=select3((x-16)>>4);endcase end',
 'if(x>=16&&y>=396&&y<412)begin text=1;row=y-396;col=(x-16)&15;glyph=help((x-16)>>4);end end',
 'end endmodule']
p=root/'src/user_source/hdl_source/video_rgb_to_axis_640x480.v';s=p.read_text(encoding='utf-8-sig');marker='// ALERT_OVERLAY_BEGIN'
if marker in s:s=s[:s.index(marker)]
p.write_text(s+'\n'+marker+'\n'+'\n'.join(lines)+'\n',encoding='utf-8')
p=root/'src/user_source/hdl_source/uart_console.v';s=p.read_text(encoding='utf-8-sig')
s=re.sub(r'glyph_argument>=\d+',f'glyph_argument>={len(mapping)}',s);p.write_text(s,encoding='utf-8')
print(f'Alert shared font: {len(mapping)} characters')
