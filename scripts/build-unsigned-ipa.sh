#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$workspace_dir"

scheme=${LEGADO_SCHEME:-Legado}
configuration=${LEGADO_CONFIGURATION:-Release}
timestamp=$(date +%Y%m%d-%H%M%S)
archive_path=${LEGADO_ARCHIVE_PATH:-"/tmp/legado-ios-${scheme}-${timestamp}.xcarchive"}
derived_data_path=${LEGADO_DERIVED_DATA_PATH:-"/tmp/legado-ios-${scheme}-derived-${timestamp}"}
output_dir=${LEGADO_IPA_OUTPUT_DIR:-"$workspace_dir/artifacts"}

mkdir -p "$output_dir"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/legado-ios-ipa.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM

echo "Building unsigned iPhoneOS archive..."
xcodebuild \
    -project Legado.xcodeproj \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=NO \
    archive

app_path=$(find "$archive_path/Products/Applications" -type d -name '*.app' -prune -print | head -n 1)
if [ -z "$app_path" ]; then
    echo "No archived .app found under: $archive_path/Products/Applications" >&2
    exit 1
fi
app_name=${app_path##*/}

if [ -n "${LEGADO_IPA_NAME:-}" ]; then
    ipa_name=$LEGADO_IPA_NAME
else
    resolved_info_plist="$app_path/Info.plist"
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$resolved_info_plist")
    build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$resolved_info_plist")
    ipa_name="legado-ios-v${version}-build${build_number}-unsigned.ipa"
fi
ipa_path="$output_dir/$ipa_name"

if [ -e "$ipa_path" ]; then
    echo "Output already exists: $ipa_path" >&2
    echo "Set LEGADO_IPA_NAME or LEGADO_IPA_OUTPUT_DIR to choose another path." >&2
    exit 2
fi

mkdir -p "$staging_dir/Payload"
cp -R "$app_path" "$staging_dir/Payload/"
staged_app="$staging_dir/Payload/$app_name"

if [ -e "$staged_app/_CodeSignature" ] || [ -e "$staged_app/embedded.mobileprovision" ]; then
    echo "The archived app contains signing material; refusing to create an unsigned IPA." >&2
    exit 1
fi

echo "Packaging $ipa_path..."
(cd "$staging_dir" && zip -qry "$ipa_path" Payload)
unzip -t "$ipa_path" >/dev/null

codesign_output=$(codesign -dvv "$staged_app" 2>&1 || true)
case "$codesign_output" in
    *"code object is not signed at all"*) ;;
    *)
        echo "The generated app is not confirmed unsigned:" >&2
        printf '%s\n' "$codesign_output" >&2
        exit 1
        ;;
esac

printf 'Created: %s\n' "$ipa_path"
printf 'Size: '
stat -f '%z bytes' "$ipa_path"
printf 'SHA-256: '
shasum -a 256 "$ipa_path" | awk '{print $1}'
