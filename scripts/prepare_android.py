from pathlib import Path
manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text()
if 'android.permission.INTERNET' not in s:s=s.replace('<application','<uses-permission android:name="android.permission.INTERNET"/>\n    <application',1)
s=s.replace('android:label="flait_expense_manage"','android:label="Flait"')
manifest.write_text(s)
p=Path('android/app/build.gradle.kts')
if p.exists():p.write_text(p.read_text().replace('minSdk = flutter.minSdkVersion','minSdk = 24'))
# Keep the local journal and device signing identity out of Android cloud backup.
manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text()
if 'android:allowBackup' not in s:
 s=s.replace('<application','<application android:allowBackup="false" android:fullBackupContent="false" android:dataExtractionRules="@xml/data_extraction_rules"',1)
manifest.write_text(s)
xml=Path('android/app/src/main/res/xml/data_extraction_rules.xml');xml.parent.mkdir(parents=True,exist_ok=True)
excludes=''.join(f'<exclude domain="{domain}" path="."/>' for domain in ['root','file','database','sharedpref','external'])
xml.write_text(f'<?xml version="1.0" encoding="utf-8"?><data-extraction-rules><cloud-backup>{excludes}</cloud-backup><device-transfer>{excludes}</device-transfer></data-extraction-rules>')
