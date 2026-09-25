# Generates the kaomoji face textures (client/assets/faces, server/public/img/faces).
# Run from client/assets: python3 ../../branding/make_faces.py
from PIL import Image, ImageDraw, ImageFont
FONT='fonts/Nunito.ttf'
FACES = {
 ':D':('grin',True), ':)':('smile',True), ':3':('cat',True), ':P':('tongue',True), ';)':('wink',True), ':O':('wow',True),
 'xD':('xd',True), 'B)':('cool',True), ':|':('flat',True), ':(':('sad',True),
 '^_^':('happy',False), 'owo':('owo',False), 'uwu':('uwu',False), '>_<':('squint',False), 'T_T':('cry',False),
 '-_-':('meh',False), '<3':('love',False),
}
INK=(28,26,34,255)
SIZE=152
WEIGHT=800
MAXW=226
def render(text, rotate):
    font=ImageFont.truetype(FONT, SIZE*4)
    font.set_variation_by_axes([WEIGHT])
    tmp=Image.new('RGBA',(SIZE*4*len(text)+400,SIZE*8),(0,0,0,0))
    ImageDraw.Draw(tmp).text((200,SIZE*2),text,font=font,fill=INK)
    tmp=tmp.crop(tmp.getbbox())
    if rotate: tmp=tmp.rotate(-90, expand=True)
    tmp=tmp.resize((tmp.width//4, tmp.height//4), Image.LANCZOS)
    if tmp.width > MAXW:
        s=MAXW/tmp.width
        tmp=tmp.resize((int(tmp.width*s), int(tmp.height*s)), Image.LANCZOS)
    out=Image.new('RGBA',(256,256),(0,0,0,0))
    out.paste(tmp,(128-tmp.width//2, 118-tmp.height//2), tmp)
    return out
for fid,(slug,rot) in FACES.items():
    img=render(fid,rot)
    img.save(f'faces/{slug}.png')
    img.save(f'/home/user/Meltiew/server/public/img/faces/{slug}.png')



pass
