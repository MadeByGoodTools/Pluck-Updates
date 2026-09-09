#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
dist_dir="$project_dir/dist"
build_dir="$(mktemp -d /tmp/appcleanup-build.XXXXXX)"
app_dir="$build_dir/Pluck.app"
trap 'rm -rf "$build_dir"' EXIT

rm -rf "$dist_dir/Pluck.app" "$dist_dir/Pluck-macOS.zip" \
  "$dist_dir/GoodTools-Installer-Pluck-macOS-Apple-Silicon.pkg"
mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

xcrun swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI \
  -framework AppKit \
  "$project_dir/Sources/Main.swift" \
  "$project_dir/Sources/EntryPoint.swift" \
  "$project_dir/Sources/CleanupEngine.swift" \
  -o "$app_dir/Contents/MacOS/Pluck"

cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/PrivacyInfo.xcprivacy" "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy"
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$dist_dir/Pluck-macOS.zip"

component_pkg="$build_dir/Pluck-component.pkg"
pkgbuild \
  --component "$app_dir" \
  --install-location /Applications \
  --identifier ca.goodtools.pluck.pkg \
  --version 0.1.0 \
  "$component_pkg"

productbuild \
  --distribution "$project_dir/Installer/Distribution.xml" \
  --package-path "$build_dir" \
  --resources "$project_dir/Installer" \
  "$dist_dir/GoodTools-Installer-Pluck-macOS-Apple-Silicon.pkg"

echo "$dist_dir/GoodTools-Installer-Pluck-macOS-Apple-Silicon.pkg"
