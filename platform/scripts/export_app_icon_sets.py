"""Export approved icon artwork into platform resource sizes using ImageMagick."""
import json
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = root / 'client/assets/qmetplus_icon.png'
cutout = root / 'branding/logo-circle.png'
icons = root / 'client/ios/Runner/Assets.xcassets/AppIcon.appiconset'
for image in json.loads((icons / 'Contents.json').read_text())['images']:
    if 'filename' not in image:
        continue
    size = round(float(image['size'].split('x')[0]) * float(image.get('scale', '1x')[:-1]))
    subprocess.run(['magick', str(source), '-resize', f'{size}x{size}', '-alpha', 'off', str(icons / image['filename'])], check=True)
for name, size in [('favicon.png', 32), ('icons/Icon-192.png', 192), ('icons/Icon-512.png', 512),
                   ('icons/Icon-maskable-192.png', 192), ('icons/Icon-maskable-512.png', 512)]:
    artwork = source if 'maskable' in name else cutout
    subprocess.run(['magick', str(artwork), '-resize', f'{size}x{size}', str(root / 'client/web' / name)], check=True)
