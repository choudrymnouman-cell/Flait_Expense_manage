from pathlib import Path
manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text()
if 'android.permission.INTERNET' not in s:s=s.replace('<application','<uses-permission android:name="android.permission.INTERNET"/>\n    <application',1)
s=s.replace('android:label="flait_expense_manage"','android:label="Expense Manage"')
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

# Stable Play application ID and biometric-capable activity.
p=Path('android/app/build.gradle.kts')
p.write_text(p.read_text().replace('com.example.flait_expense_manage','com.flait.expenses'))
manifest=Path('android/app/src/main/AndroidManifest.xml');s=manifest.read_text()
if 'android.permission.USE_BIOMETRIC' not in s:
 s=s.replace('<application','<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application',1)
s=s.replace('android:name=".MainActivity"','android:name="com.flait.expenses.MainActivity"')
manifest.write_text(s)
for source in Path('android/app/src/main/kotlin').rglob('MainActivity.kt'):
 if 'com.flait.expenses' not in source.read_text():
  # Only replace Flutter's generated default activity, never unrelated sources.
  content=source.read_text()
  if 'class MainActivity' in content and ('FlutterActivity' in content or 'FlutterFragmentActivity' in content): source.unlink()
activity=Path('android/app/src/main/kotlin/com/flait/expenses/MainActivity.kt');activity.parent.mkdir(parents=True,exist_ok=True)
if not activity.exists(): activity.write_text('package com.flait.expenses\n\nimport io.flutter.embedding.android.FlutterFragmentActivity\n\nclass MainActivity : FlutterFragmentActivity()\n')
for name in ['values','values-night','values-v31','values-night-v31']:
 styles=Path('android/app/src/main/res')/name/'styles.xml'
 if styles.exists():
  styles.write_text(styles.read_text().replace('@android:style/Theme.Light.NoTitleBar','Theme.AppCompat.DayNight.NoActionBar').replace('@android:style/Theme.Black.NoTitleBar','Theme.AppCompat.DayNight.NoActionBar'))
