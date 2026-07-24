#!/bin/bash

set -e
set -x

conda_env="Parashell.app/Contents/Resources"

mkdir -p ${conda_env}

cp -a ../.pixi/envs/default/* ${conda_env}

# delete unnecessary stuff
rm -rf ${conda_env}/include
find ${conda_env} -name \*.a -delete

mv ${conda_env}/bin ${conda_env}/bin_tmp
mkdir ${conda_env}/bin
cp ${conda_env}/bin_tmp/freecad ${conda_env}/bin/
cp ${conda_env}/bin_tmp/freecadcmd ${conda_env}/bin
cp ${conda_env}/bin_tmp/ccx ${conda_env}/bin/
cp ${conda_env}/bin_tmp/python ${conda_env}/bin/
cp ${conda_env}/bin_tmp/pip ${conda_env}/bin/
cp ${conda_env}/bin_tmp/pyside6-rcc ${conda_env}/bin/
cp ${conda_env}/bin_tmp/gmsh ${conda_env}/bin/
cp ${conda_env}/bin_tmp/dot ${conda_env}/bin/
cp ${conda_env}/bin_tmp/unflatten ${conda_env}/bin/
rm -rf ${conda_env}/bin_tmp

sed -i '1s|.*|#!/usr/bin/env python|' ${conda_env}/bin/pip

# copy resources
cp resources/* ${conda_env}
chmod +x ${conda_env}/uninstall.command

# Remove __pycache__ folders and .pyc files
find . -path "*/__pycache__/*" -delete
find . -name "*.pyc" -type f -delete

# fix problematic rpaths and reexport_dylibs for signing
# see https://github.com/FreeCAD/FreeCAD/issues/10144#issuecomment-1836686775
# and https://github.com/FreeCAD/FreeCAD-Bundle/pull/203
# and https://github.com/FreeCAD/FreeCAD-Bundle/issues/375
python ../scripts/fix_macos_lib_paths.py ${conda_env}/lib -r

# build and install the launcher
cmake -B build launcher
cmake --build build
mkdir -p Parashell.app/Contents/MacOS
cp build/Parashell Parashell.app/Contents/MacOS/Parashell

# Download, verify, and embed the Sparkle framework used by the in-app auto-updater
SPARKLE_VERSION="2.9.4"
SPARKLE_SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"
sparkle_dir="$(pwd)/sparkle-${SPARKLE_VERSION}"
sparkle_archive="${sparkle_dir}.tar.xz"
if [ ! -d "${sparkle_dir}/Sparkle.framework" ]; then
    mkdir -p "${sparkle_dir}"
    curl -fSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "${sparkle_archive}"
    echo "${SPARKLE_SHA256}  ${sparkle_archive}" | shasum -a 256 -c -
    tar -xJf "${sparkle_archive}" -C "${sparkle_dir}"
fi
mkdir -p Parashell.app/Contents/Frameworks
cp -R "${sparkle_dir}/Sparkle.framework" Parashell.app/Contents/Frameworks/

# Add deployment target suffix to artifact name (e.g., "-macOS11" or "-macOS15")
deploy_target="${MACOS_DEPLOYMENT_TARGET:-11.0}"
version_name="Parashell_${BUILD_TAG}-macOS${deploy_target%%.*}-$(uname -m)"
application_menu_name="Parashell_${BUILD_TAG}"

echo -e "\################"
echo -e "version_name:  ${version_name}"
echo -e "################"

# Extract Apple-compliant bundle version from version.json
# For dev/weekly builds, append a "d" + ISO week number suffix (e.g. "1.2.0d12")
# per Apple's CFBundleVersion spec for development builds
bundle_version=$(python3 -c "
import json, datetime
d = json.load(open('../../../version.json'))
v = f'{d[\"version_major\"]}.{d[\"version_minor\"]}.{d[\"version_patch\"]}'
suffix = d.get('version_suffix', '')
if suffix:
    week = datetime.date.today().isocalendar()[1]
    v += f'd{week}'
print(v)
")

cp Info.plist.template ${conda_env}/../Info.plist
sed -i "s/FREECAD_BUNDLE_VERSION/${bundle_version}/" ${conda_env}/../Info.plist
sed -i "s/APPLICATION_MENU_NAME/${application_menu_name}/" ${conda_env}/../Info.plist
sed -i "s|SPARKLE_PUBLIC_ED_KEY|${SPARKLE_PUBLIC_ED_KEY:-}|" ${conda_env}/../Info.plist

pixi list -e default > Parashell.app/Contents/packages.txt
sed -i '1s/.*/\nLIST OF PACKAGES:/' Parashell.app/Contents/packages.txt

echo "Running FreeCAD command-line smoke test..."
if ! "${conda_env}/bin/freecadcmd" --safe-mode --version; then
    echo "FreeCAD command-line smoke test failed; the macOS bundle cannot start."
    exit 1
fi

echo "Running FreeCAD bundled Pivy smoke test..."
if ! "${conda_env}/bin/freecadcmd" --safe-mode --console "import pivy; from pivy import coin; print(pivy.__file__); print(coin.SoDB.getVersion())"; then
    echo "FreeCAD bundled Pivy smoke test failed; the macOS bundle cannot import the bundled Coin/Pivy runtime."
    exit 1
fi

# move plugins into their final location (Library only exists for macOS < 15.0 builds)
if [ -d "${conda_env}/Library" ]; then
    mv ${conda_env}/Library ${conda_env}/..
fi

# move App Extensions (PlugIns) to the correct location for macOS registration
if [ -d "${conda_env}/PlugIns" ]; then
    mv ${conda_env}/PlugIns ${conda_env}/..
fi

if [[ "${MACOS_SIGN_RELEASE}" == "true" ]]; then
    # create the signed dmg
    ../../scripts/macos_sign_and_notarize.zsh -p "Parashell" -k ${MACOS_SIGNING_KEY_ID} -n "Parashell.app" -o "${version_name}.dmg"
else
    # Ad-hoc sign for local builds (required for QuickLook extensions to register)
    if [ -d "Parashell.app/Contents/PlugIns" ]; then
        echo "Ad-hoc signing App Extensions with entitlements..."
        codesign --force --sign - \
            --entitlements ../../../src/MacAppBundle/QuickLook/modern/ThumbnailExtension.entitlements \
            Parashell.app/Contents/PlugIns/FreeCADThumbnailExtension.appex
        codesign --force --sign - \
            --entitlements ../../../src/MacAppBundle/QuickLook/modern/PreviewExtension.entitlements \
            Parashell.app/Contents/PlugIns/FreeCADPreviewExtension.appex
    fi
    echo "Ad-hoc signing app bundle..."
    if [ -d "Parashell.app/Contents/Frameworks/Sparkle.framework" ]; then
        echo "Ad-hoc signing Sparkle framework..."
        codesign --force --deep --sign - Parashell.app/Contents/Frameworks/Sparkle.framework
    fi
    codesign --force --sign - Parashell.app/Contents/packages.txt
    if [ -f "Parashell.app/Contents/Library/QuickLook/QuicklookFCStd.qlgenerator/Contents/MacOS/QuicklookFCStd" ]; then
        codesign --force --sign - Parashell.app/Contents/Library/QuickLook/QuicklookFCStd.qlgenerator/Contents/MacOS/QuicklookFCStd
    fi
    codesign --force --sign - Parashell.app

    # create the dmg
    dmgbuild -s dmg_settings.py "Parashell" "${version_name}.dmg"
fi

# create hash
sha256sum ${version_name}.dmg > ${version_name}.dmg-SHA256.txt

# Optionally produce the Sparkle EdDSA signature sidecar for the finalized dmg
# so the appcast feed can advertise a verifiable enclosure. This mirrors the
# Apple/Azure signing gates: it is entirely opt-in via SPARKLE_ED_PRIVATE_KEY
# and never fails the build when the key is absent or signing does not succeed.
release_files=("${version_name}.dmg" "${version_name}.dmg-SHA256.txt")
sparkle_sign_update="${sparkle_dir}/bin/sign_update"
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] && [ -x "${sparkle_sign_update}" ]; then
    echo "Signing dmg with Sparkle EdDSA key for the appcast feed..."
    key_file="$(mktemp)"
    printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" > "${key_file}"
    sig_output="$("${sparkle_sign_update}" --ed-key-file "${key_file}" "${version_name}.dmg" 2>/dev/null || true)"
    rm -f "${key_file}"
    ed_signature="$(printf '%s' "${sig_output}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    dmg_length="$(printf '%s' "${sig_output}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
    if [ -z "${dmg_length}" ]; then
        dmg_length="$(stat -f%z "${version_name}.dmg")"
    fi
    if [ -n "${ed_signature}" ]; then
        printf '{"edSignature": "%s", "length": %s}\n' "${ed_signature}" "${dmg_length}" > "${version_name}.dmg.sparkle.json"
        release_files+=("${version_name}.dmg.sparkle.json")
    else
        echo "Sparkle EdDSA signing produced no signature; skipping appcast sidecar."
    fi
else
    echo "SPARKLE_ED_PRIVATE_KEY not set; skipping Sparkle appcast signature sidecar."
fi

if [[ "${UPLOAD_RELEASE}" == "true" ]]; then
    for attempt in 1 2 3 4 5; do
        if gh release upload --clobber ${BUILD_TAG} "${release_files[@]}"; then
            break
        fi
        if [[ $attempt -eq 5 ]]; then
            echo "Failed to upload release after 5 attempts" >&2
            exit 1
        fi
        echo "Upload attempt $attempt failed, retrying in $((attempt * 10))s..."
        sleep $((attempt * 10))
    done
fi
