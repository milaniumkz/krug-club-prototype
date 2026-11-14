#!/bin/sh
set -eu
cd "$(dirname "$0")/../client"
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
mkdir -p ../web
cp -R build/web/. ../web/
case "${1:-debug}" in
  debug)
    flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000
    ;;
  release)
    case "${API_BASE_URL:?Set your HTTPS API origin}" in https://*) ;; *) echo 'Release API must use HTTPS'; exit 1;; esac
    flutter build appbundle --release --dart-define="API_BASE_URL=$API_BASE_URL"
    ;;
  ios-check)
    case "${API_BASE_URL:?Set HTTPS API origin}" in https://*) ;; *) exit 1;; esac
    flutter config --no-enable-swift-package-manager
    flutter build ios --release --no-codesign --dart-define="API_BASE_URL=$API_BASE_URL"
    ;;
esac
