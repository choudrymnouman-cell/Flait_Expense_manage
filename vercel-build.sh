#!/usr/bin/env bash
set -euo pipefail

if [ ! -d /tmp/flutter-sdk ]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /tmp/flutter-sdk
fi
export PATH="/tmp/flutter-sdk/bin:$PATH"
flutter config --enable-web
flutter pub get
flutter build web --release --base-href /
