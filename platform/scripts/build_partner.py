"""Build an independently installable partner app without modifying the member project."""

import argparse, pathlib, plistlib, shutil, subprocess
from urllib.parse import urlsplit

p = argparse.ArgumentParser()
p.add_argument("--platform", choices=["android", "ios"], default="android")
p.add_argument("--mode", choices=["debug", "release"], default="debug")
p.add_argument("--prepare-only", action="store_true")
p.add_argument("--android-signing-file", type=pathlib.Path)
p.add_argument("--output", type=pathlib.Path)
p.add_argument('--bundle', action='store_true', help='Build signed Android App Bundle')
p.add_argument('--ipa', action='store_true', help='Build signed iOS App Store archive')
p.add_argument('--api-base-url', default='https://qazaqmetalpartners.109.235.119.144.sslip.io')
a = p.parse_args()
if a.bundle and a.platform != 'android':p.error('--bundle requires Android')
if a.ipa and a.platform != 'ios':p.error('--ipa requires iOS')
url = urlsplit(a.api_base_url)
if url.scheme != 'https' or not url.hostname or url.hostname in ('localhost', '127.0.0.1', '10.0.2.2') or url.username or url.password or url.path not in ('', '/') or url.query or url.fragment:
    p.error('A public HTTPS API origin is required')
root = pathlib.Path(__file__).resolve().parents[1]
out = (a.output or root / "client/build/partner-app").resolve()
out.mkdir(parents=True, exist_ok=True)
# The prepared independent source target is also usable for Xcode signing later.
target = out / "source"
if target.exists():
    if not (target / ".qazaqmetal-generated-partner").is_file():
        raise SystemExit("Existing source preserved: choose another output directory")
    shutil.rmtree(target)
shutil.copytree(
    root / "client",
    target,
    ignore=shutil.ignore_patterns(
        "build",
        ".dart_tool",
        ".git",
        ".env",
        "key.properties",
        "google-services.json",
        "GoogleService-Info.plist",
        ".gradle",
        "Pods",
        ".symlinks",
        "*.jks",
        "*.keystore",
    ),
)
(target / ".qazaqmetal-generated-partner").write_text(
    "Generated independent partner build target; safe to regenerate.\n"
)
old = "kz.qazaqmetal.qazaqmetal"
new = old + ".partner"
gradle = target / "android/app/build.gradle.kts"
s = gradle.read_text()
s = s.replace('applicationId = "' + old + '"', 'applicationId = "' + new + '"')
gradle.write_text(s)
manifest = target / "android/app/src/main/AndroidManifest.xml"
manifest.write_text(
    manifest.read_text()
    .replace('android:label="QMET+"', 'android:label="QMET+ Партнёр"')
    .replace(
        'android:name=".MainActivity"',
        'android:name="kz.qazaqmetal.qazaqmetal.MainActivity"',
    )
)
pbx = target / "ios/Runner.xcodeproj/project.pbxproj"
pbx.write_text(
    pbx.read_text().replace(
        "PRODUCT_BUNDLE_IDENTIFIER = " + old, "PRODUCT_BUNDLE_IDENTIFIER = " + new
    )
)
info = target / "ios/Runner/Info.plist"
with info.open("rb") as f:
    data = plistlib.load(f)
data["CFBundleDisplayName"] = "QMET+ Партнёр"
data["CFBundleName"] = "qmetplus_partner"
with info.open("wb") as f:
    plistlib.dump(data, f)
from configure_firebase_native import configure
configure(target, 'partner')
if a.android_signing_file:
    shutil.copy2(a.android_signing_file.resolve(), target / "android/key.properties")
if a.prepare_only:
    print("Prepared partner target:", target)
    raise SystemExit(0)
command = [
    "flutter",
    "build",
    ('appbundle' if a.bundle else 'apk') if a.platform == 'android' else ('ipa' if a.ipa else 'ios'),
    "--" + a.mode,
    "--dart-define=PORTAL=partner",
    '--dart-define=API_BASE_URL=' + a.api_base_url.rstrip('/'),
]
if a.platform == "ios" and not a.ipa:
    command.append("--no-codesign")
subprocess.run(command, cwd=target, check=True)
if a.platform == "android":
    result = out / ('QMETplus_Partner_' + a.mode + ('.aab' if a.bundle else '.apk'))
    artifact = target / (f'build/app/outputs/bundle/{a.mode}/app-{a.mode}.aab' if a.bundle else f'build/app/outputs/flutter-apk/app-{a.mode}.apk')
    shutil.copy2(artifact, result)
elif a.ipa:
    result = out / 'ipa'
    shutil.copytree(target / 'build/ios/ipa', result, dirs_exist_ok=True)
else:
    result = out / "QazaqMetal_Partner_iOS_unsigned.zip"
    subprocess.run(
        [
            "ditto",
            "-c",
            "-k",
            "--keepParent",
            str(target / "build/ios/iphoneos/Runner.app"),
            str(result),
        ],
        check=True,
    )
print("Partner build:", result)
