#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# SwiftPM always adds the XCTest search paths, which Command Line Tools do not ship, so the linker warns about them.
swift build -c release --product HardydoNotes 2>&1 \
    | { grep -v "search path '/Library/Developer/CommandLineTools/Developer/.*' not found" || true; }
bin="$(swift build -c release --show-bin-path)/HardydoNotes"

app="dist/Hardydo Notes.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/HardydoNotes"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp .build/checkouts/swift-cmark/COPYING "$app/Contents/Resources/swift-cmark-COPYING.txt"
cp -R Resources/highlight "$app/Contents/Resources/highlight"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>HardydoNotes</string>
    <key>CFBundleIdentifier</key><string>com.hardydo.drivenotes</string>
    <key>CFBundleName</key><string>Hardydo Notes</string>
    <key>CFBundleDisplayName</key><string>Hardydo Notes</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Hardydo. MIT License.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Text Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>net.daringfireball.markdown</string>
                <string>public.json</string>
                <string>public.xml</string>
                <string>public.html</string>
                <string>public.yaml</string>
                <string>public.source-code</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key><string>Markdown</string>
            <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>md</string><string>markdown</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# A stable signing identity lets macOS treat every rebuild as the same app; ad-hoc signing also works.
identity="${HARDYDO_SIGN_IDENTITY:-Hardydo Notes Dev}"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
    codesign --force --sign "$identity" "$app"
    echo "Signed with \"$identity\""
else
    codesign --force --sign - "$app"
    echo "Signed ad-hoc"
fi
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Hardydo Notes.app"
    mv "$app" "$HOME/Applications/Hardydo Notes.app"
    echo "Installed to ~/Applications/Hardydo Notes.app"
fi
