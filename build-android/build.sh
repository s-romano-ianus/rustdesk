#!/usr/bin/env bash
# DareMoto: build of the universal APK (arm64 + armv7) inside the container.
# /src  host repository (read only): the build uses its committed HEAD, plus the
#       flutter_rust_bridge files generated on the host (not in git)
# /out  where the unsigned APK goes
# Caches (Docker volumes): /cache/target, /cache/vcpkg-bin, /opt/vcpkg/installed, ...
set -euo pipefail

: "${RENDEZVOUS_SERVER:?}" "${RS_PUB_KEY:?}" "${VERSION:?}"
export RENDEZVOUS_SERVER RS_PUB_KEY API_SERVER="${API_SERVER:-}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a}"

step() { echo; echo "==> $*"; }

step "Sorgenti: HEAD del repository"
rm -rf /work
git clone -q /src /work
cd /work
git submodule init -q
git config submodule.libs/hbb_common.url /src/libs/hbb_common
git -c protocol.file.allow=always submodule update -q
echo "commit $(git rev-parse --short HEAD), hbb_common $(git -C libs/hbb_common rev-parse --short HEAD)"

step "File del bridge generati sull'host"
for f in src/bridge_generated.rs src/bridge_generated.io.rs \
         flutter/lib/generated_bridge.dart flutter/lib/generated_bridge.freezed.dart \
         flutter/macos/Runner/bridge_generated.h; do
  cp "/src/$f" "/work/$f"
done
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h

step "Patch di Flutter"
if git -C /opt/flutter apply --check /work/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff 2>/dev/null; then
  git -C /opt/flutter apply /work/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff
fi

export CARGO_TARGET_DIR=/cache/target
for abi in $ABIS; do
  case $abi in
    arm64-v8a)   target=aarch64-linux-android;   script=ndk_arm64.sh; libcxx=aarch64-linux-android ;;
    armeabi-v7a) target=armv7-linux-androideabi; script=ndk_arm.sh;   libcxx=arm-linux-androideabi ;;
    *) echo "ABI non supportata: $abi"; exit 1 ;;
  esac
  step "Dipendenze vcpkg $abi (la prima volta richiede molto tempo)"
  if ! ./flutter/build_android_deps.sh "$abi"; then
    find "$VCPKG_ROOT/buildtrees" -name "*-err.log" -newer /work/Cargo.toml -exec sh -c 'echo "--- $1"; tail -40 "$1"' _ {} \;
    exit 1
  fi
  step "librustdesk $abi (server $RENDEZVOUS_SERVER)"
  bash "./flutter/$script"
  dest=flutter/android/app/src/main/jniLibs/$abi
  mkdir -p "$dest"
  cp "$CARGO_TARGET_DIR/$target/release/liblibrustdesk.so" "$dest/librustdesk.so"
  cp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$libcxx/libc++_shared.so" "$dest/"
done

step "APK"
# Docker has no IPv6 route: Java would try it first and fail to download the plugins
export JAVA_TOOL_OPTIONS="-Djava.net.preferIPv4Stack=true"
sed -i "s/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx2g/g" flutter/android/gradle.properties
# debug signature: the DareMoto key is applied on the host (build-android-sign.ps1)
sed -i "s/signingConfigs.release/signingConfigs.debug/g" flutter/android/app/build.gradle
platforms=""
for abi in $ABIS; do
  case $abi in arm64-v8a) platforms+="android-arm64," ;; armeabi-v7a) platforms+="android-arm," ;; esac
done
(cd flutter && flutter build apk --release --target-platform "${platforms%,}")
out="/out/daremoto-$VERSION-unsigned.apk"
cp flutter/build/app/outputs/flutter-apk/app-release.apk "$out"
echo
echo "OK -> daremoto-$VERSION-unsigned.apk ($(du -h "$out" | cut -f1))"
