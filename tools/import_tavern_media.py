"""Convert retained generated menu sources into WoW-compatible RGBA TGA assets."""
from pathlib import Path
from PIL import Image
import hashlib, json

root = Path(__file__).resolve().parents[1]
report = {}
for name, size in [('tavern-cabinet', (2048,1024)), ('tavern-button', (1024,256))]:
    source = root/'tools/menu-assets'/f'{name}.png'
    im = Image.open(source).convert('RGBA')
    im.resize(size, Image.Resampling.LANCZOS).save(root/'ForeverHearthstone/Art'/f'{name}.tga')
    report[name] = {'source': f'tools/menu-assets/{name}.png',
                    'provenance': 'OpenAI image generation, September 23 2026; original Hearthstone-inspired artwork',
                    'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                    'original_size': im.size, 'texture_size': size}
(root/'ForeverHearthstone/Art/tavern-media-report.json').write_text(json.dumps(report,indent=2))
