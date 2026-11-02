from pathlib import Path
import hashlib,urllib.request
FONTS = [{'name': 'NotoSans-Regular.ttf', 'url': 'https://raw.githubusercontent.com/notofonts/noto-fonts/ffebf8c1ee449e544955a7e813c54f9b73848eac/hinted/ttf/NotoSans/NotoSans-Regular.ttf', 'sha256': 'b85c38ecea8a7cfb39c24e395a4007474fa5a4fc864f6ee33309eb4948d232d5'}, {'name': 'NotoNaskhArabic-Regular.ttf', 'url': 'https://raw.githubusercontent.com/notofonts/noto-fonts/ffebf8c1ee449e544955a7e813c54f9b73848eac/hinted/ttf/NotoNaskhArabic/NotoNaskhArabic-Regular.ttf', 'sha256': '2f4b88e6ee50fa82c617e2d1d4ba18281cb1c6cd71c3af3ec64970c23995db4b'}]
for asset in FONTS:
 path=Path('assets/fonts')/asset['name'];path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()==asset['sha256']:continue
 with urllib.request.urlopen(asset['url'],timeout=90) as response:data=response.read()
 if hashlib.sha256(data).hexdigest()!=asset['sha256']:raise RuntimeError('Font checksum mismatch')
 path.write_bytes(data)
print('Bundled offline fonts verified')
