"""Convert menu source artwork to WoW textures; preserve provenance.
Run with the bundled Python + Pillow runtime. Source downloads are retained.
"""
from pathlib import Path
import hashlib,json
from PIL import Image
root=Path(__file__).resolve().parents[1]
src=root/'tools/menu-assets'; dest=root/'ForeverHearthstone/Art'
mapping={
 'menu-parchment':('arena-parchment.jpg','Manacost-Labs/HeartPulse/main/public/wallpaper/'),
 'menu-leather':('arena-rail-red.jpg','Manacost-Labs/HeartPulse/main/public/wallpaper/'),
 'menu-border':('deck-border.png','Manacost-Labs/HeartPulse/main/public/wallpaper/'),
 'menu-nav':('nav-bg.png','Manacost-Labs/HeartPulse/main/public/wallpaper/'),
 'menu-pack-room':('openpacksbackground.png','Rymedy/hearthstone-web/master/src/images/'),
 'menu-pack':('pack.png','Rymedy/hearthstone-web/master/src/images/'),
 'menu-chest':('mainmenubackground.jpg','Rymedy/hearthstone-web/master/src/images/'),
}
report={}
for name,(file,source) in mapping.items():
 data=(src/file).read_bytes(); im=Image.open(src/file).convert('RGBA')
 size=tuple(min(2048,2**(v-1).bit_length()) for v in im.size)
 im.resize(size,Image.Resampling.LANCZOS).save(dest/(name+'.tga'))
 report[name]={'source':'https://raw.githubusercontent.com/'+source+file,'sha256':hashlib.sha256(data).hexdigest(),'original_size':im.size,'texture_size':size}
(dest/'menu-media-report.json').write_text(json.dumps(report,indent=2))
