#!/usr/bin/env bash
# Builds the Flutter web app on Vercel (Flutter is not preinstalled there).
set -euo pipefail

FLUTTER_DIR="${HOME}/flutter"

if [[ ! -d "${FLUTTER_DIR}/bin" ]]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

flutter config --enable-web
flutter precache --web
flutter pub get
flutter build web --release --base-href /
