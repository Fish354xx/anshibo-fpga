"""Add event-area prefix to the shared font and generate event field placement."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
p=root/'tools/build_alert_overlay.py';s=p.read_text(encoding='utf-8-sig')
s=s.replace("'help':'KEY2选择  KEY3确认'", "'help':'KEY2选择  KEY3确认','area_prefix':'区域：'")
p.write_text(s,encoding='utf-8');exec(compile(s,str(p),'exec'),{'__file__':str(p)})
mapping={e['character']:e['id'] for e in json.loads((root/'tools/text_font.json').read_text(encoding='utf-8'))}
lines=['module event_text_layout(input[9:0]x,y,scroll,input[1:0]level,',
 'input[4:0]area_length,input[6:0]body_length,input[9:0]data,',
 'output reg[6:0]read_index,output reg band,text,output reg[9:0]glyph,',
 'output reg[3:0]row,col,output reg[23:0]background,ink);']
for name,value in [('area_prefix','区域：'),('reminder_prefix','一级提醒：')]:
 lines += [f'function[9:0]{name};input[5:0]i;begin case(i)']
 lines += [f"{i}:{name}=10'd{mapping[c]};" for i,c in enumerate(value)]
 lines += [f'default:{name}=0;endcase end endfunction']
lines += ['wire[9:0]body_x=x+scroll;', 'wire[9:0]reminder_x=x-112+scroll;',
 'reg[6:0]position;always @(*)begin',
 "band=0;text=0;glyph=0;row=0;col=0;read_index=0;position=0;background=24'h182838;ink=24'hFFFFFF;",
 'if(level==1&&y>=392&&y<416)begin band=1;',
 'if(y>=396&&y<412&&x>=16&&x<64)begin text=1;row=y-396;col=(x-16)&15;glyph=area_prefix((x-16)>>4);end',
 'if(y>=396&&y<412&&x>=64&&x<320)begin text=1;row=y-396;col=(x-64)&15;read_index=(x-64)>>4;glyph=(read_index<area_length)?data:0;end end',
 "if(level==1&&y>=416&&y<440)begin band=1;background=24'hFFC040;ink=24'h182838;",
 'if(y>=420&&y<436&&x>=16&&x<96)begin text=1;row=y-420;col=(x-16)&15;glyph=reminder_prefix((x-16)>>4);end',
 'if(y>=420&&y<436&&x>=112&&x<624)begin text=1;row=y-420;col=reminder_x[3:0];position=reminder_x[9:4];read_index=16+position;glyph=(position<body_length)?data:0;end end',
 'if(level==2&&y>=160&&y<320)begin band=1;',
 'if(y>=180&&y<196&&x>=96&&x<144)begin text=1;row=y-180;col=(x-96)&15;glyph=area_prefix((x-96)>>4);end',
 'if(y>=180&&y<196&&x>=144&&x<400)begin text=1;row=y-180;col=(x-144)&15;read_index=(x-144)>>4;glyph=(read_index<area_length)?data:0;end']
for n in range(4):
 lines += [f'if(y>={224+n*24}&&y<{240+n*24}&&x>=96&&x<352)begin',
 f'text=1;row=y-{224+n*24};col=(x-96)&15;position={n*16}+((x-96)>>4);read_index=16+position;glyph=(position<body_length)?data:0;end']
lines += ['end',
 'if(level==3&&y>=156&&y<188)begin band=1;',
 'if(y>=164&&y<180&&x>=16&&x<64)begin text=1;row=y-164;col=(x-16)&15;glyph=area_prefix((x-16)>>4);end',
 'if(y>=164&&y<180&&x>=64&&x<320)begin text=1;row=y-164;col=(x-64)&15;read_index=(x-64)>>4;glyph=(read_index<area_length)?data:0;end end',
 "if(level==3&&y>=440&&y<472)begin band=1;background=24'hBA2028;",
 'if(y>=448&&y<464)begin text=1;row=y-448;col=body_x[3:0];position=body_x[9:4];read_index=16+position;glyph=(position<body_length)?data:0;end end',
 'end endmodule']
p=root/'src/user_source/hdl_source/video_rgb_to_axis_640x480.v';s=p.read_text(encoding='utf-8-sig')
marker='// EVENT_LAYOUT_BEGIN'
if marker in s:s=s[:s.index(marker)]
p.write_text(s+'\n'+marker+'\n'+'\n'.join(lines)+'\n',encoding='utf-8')
p=root/'src/user_source/hdl_source/event_packet_buffer.v';s=p.read_text(encoding='utf-8')
s=re.sub(r'FONT_COUNT=\d+',f'FONT_COUNT={len(mapping)}',s);p.write_text(s,encoding='utf-8')
print(f'Event font entries: {len(mapping)}')
