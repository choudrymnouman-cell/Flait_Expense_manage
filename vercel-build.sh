#!/usr/bin/env bash
set -euo pipefail
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true

if [ ! -d /tmp/flutter-sdk ]; then
  git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git /tmp/flutter-sdk
fi
export PATH="/tmp/flutter-sdk/bin:$PATH"
flutter config --enable-web
flutter create . --project-name flait_expense_manage --platforms=web --no-pub
python3 scripts/remove_generated_test.py
flutter pub get
flutter build web --release --base-href / --no-web-resources-cdn

python3 scripts/offline_cache.py
