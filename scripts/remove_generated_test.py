from pathlib import Path
p=Path('test/widget_test.dart')
if p.exists():
 text=p.read_text()
 if 'MyApp' in text and 'Counter increments smoke test' in text:
  p.unlink()
 else:
  raise SystemExit('Preserving unexpected widget_test.dart; review it instead of deleting it.')
