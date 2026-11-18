"""Printable public partner QR posters. No login credentials are included."""
import argparse,base64,html,json
from pathlib import Path
import qrcode
parser=argparse.ArgumentParser();parser.add_argument('state',type=Path);parser.add_argument('--output',type=Path,default=Path('demo-qr'));args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
state=json.loads(args.state.read_text());cards=[]
logo=Path(__file__).resolve().parents[2]/'platform/client/assets/logo.png'
logo_url='data:image/png;base64,'+base64.b64encode(logo.read_bytes()).decode() if logo.exists() else ''
for i,p in enumerate(state['partners'],1):
 name=f'QazaqMetal_partner_{i:02d}_QR.png'
 qr=qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,box_size=18,border=4);qr.add_data(p['code']);qr.make(fit=True);qr.make_image(fill_color='black',back_color='white').save(args.output/name)
 cards.append(f'''<section><header><img class="logo" src="{logo_url}"><div class="brand">QAZAQMETAL <span>KÁSIPODAǴY</span></div></header><p class="eyebrow">ДЕМОНСТРАЦИОННЫЙ ПАРТНЁР · {i:02d}</p><h1>{html.escape(p['name'].replace('ДЕМО · ',''))}</h1><div class="discount">−{p['percent']}%</div><p>Тестовая привилегия для членов профсоюза</p><div class="qr"><img src="{name}"></div><h2>Откройте раздел QR в приложении</h2><p class="how">Войдите в свой аккаунт, нажмите QR в нижнем меню<br>и наведите камеру на этот код.<br>Приложение само определит партнёра.</p><div class="notice">Тестовое заведение и предложение. Результат сканирования<br>не подтверждает реальную скидку.</div><footer>qazaqmetal.109.235.119.144.sslip.io</footer></section>''')
style='''@page{size:A4;margin:0}*{box-sizing:border-box}body{margin:0;color:#251a2c;font-family:Arial,sans-serif}section{height:296mm;padding:14mm 15mm;text-align:center;background:#faf6f2;page-break-after:always;position:relative}section:last-child{page-break-after:auto}header{display:flex;justify-content:center;align-items:center;gap:18px}.logo{width:80px;height:80px;border-radius:50%}.brand{font-size:24px;font-weight:700;letter-spacing:4px;color:#56289f}.brand span{display:block;font-size:14px;letter-spacing:5px;margin-top:7px}.eyebrow{font-size:12px;letter-spacing:2px;color:#785e94;margin:30px 0 12px}h1{font-family:Georgia,serif;font-size:34px;margin:0 0 10px}.discount{font-family:Georgia,serif;color:#722ed1;font-size:68px;font-weight:bold}p{font-size:16px;line-height:1.6}.qr{margin:14px auto;width:340px;height:340px;background:white;border-radius:22px;border:1px solid #e4d8ed;padding:14px}.qr img{width:100%;height:100%;image-rendering:pixelated}h2{font-size:22px;margin:22px 0 8px}.how{font-size:16px}.notice{background:#ece2f6;border-radius:16px;padding:15px;font-size:14px;line-height:1.6;margin-top:22px}footer{position:absolute;bottom:16mm;left:0;right:0;color:#75568f;font-size:13px}'''
(args.output/'QR_posters.html').write_text('<!doctype html><html lang="ru"><meta charset="utf-8"><style>'+style+'</style>'+''.join(cards)+'</html>')
print('Generated public QR PNGs and printable HTML')
