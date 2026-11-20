"""Resize the original QAZAQMETAL artwork without redrawing or recoloring it."""
import json
from pathlib import Path
from PIL import Image

client = Path(__file__).resolve().parents[1] / 'client'
logo = Image.open(client / 'assets/logo.png').convert('RGB')
def save(path, size, inset=0):
    canvas = Image.new('RGB', (size, size), 'white')
    side = round(size * (1 - inset * 2))
    art = logo.resize((side, side), Image.Resampling.LANCZOS)
    canvas.paste(art, ((size - side) // 2, (size - side) // 2))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, optimize=True)

save(client / 'assets/qmetplus_icon.png', 1024)
save(client / 'android/app/src/main/res/drawable/ic_qmetplus.png', 512)
for density, pixels in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    save(client / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', pixels)
icons = client / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons / 'Contents.json').read_text())['images']:
    if entry.get('filename'):
        pixels = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
        save(icons / entry['filename'], pixels)
for scale in (1,2,3):
    save(client / 'ios/Runner/Assets.xcassets/LaunchImage.imageset' / ('LaunchImage' + (f'@{scale}x' if scale > 1 else '') + '.png'), 160 * scale)
save(client / 'web/favicon.png', 32)
for size in (192,512):
    save(client / f'web/icons/Icon-{size}.png', size)
    save(client / f'web/icons/Icon-maskable-{size}.png', size, inset=.1)
print('Generated native, web and launch assets from the original QAZAQMETAL logo.')
