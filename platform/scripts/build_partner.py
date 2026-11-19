"""Build an independently installable partner app without modifying the member project."""

import argparse, pathlib, plistlib, shutil, subprocess

p = argparse.ArgumentParser()
p.add_argument("--platform", choices=["android", "ios"], default="android")
p.add_argument("--mode", choices=["debug", "release"], default="debug")
p.add_argument("--prepare-only", action="store_true")
p.add_argument("--android-signing-file", type=pathlib.Path)
p.add_argument("--output", type=pathlib.Path)
a = p.parse_args()
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
    .replace('android:label="QAZAQMETAL"', 'android:label="QAZAQMETAL Партнёр"')
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
data["CFBundleDisplayName"] = "QAZAQMETAL Партнёр"
data["CFBundleName"] = "qzm_partner"
with info.open("wb") as f:
    plistlib.dump(data, f)
if a.android_signing_file:
    shutil.copy2(a.android_signing_file.resolve(), target / "android/key.properties")
if a.prepare_only:
    print("Prepared partner target:", target)
    raise SystemExit(0)
command = [
    "flutter",
    "build",
    "apk" if a.platform == "android" else "ios",
    "--" + a.mode,
    "--dart-define=PORTAL=partner",
    "--dart-define=API_BASE_URL=https://qazaqmetalpartners.109.235.119.144.sslip.io",
]
if a.platform == "ios":
    command.append("--no-codesign")
subprocess.run(command, cwd=target, check=True)
if a.platform == "android":
    result = out / ("QazaqMetal_Partner_" + a.mode + ".apk")
    shutil.copy2(target / f"build/app/outputs/flutter-apk/app-{a.mode}.apk", result)
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
