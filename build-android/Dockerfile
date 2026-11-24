# DareMoto: toolchain to build the Android APK locally (same versions as
# .github/workflows/daremoto-android.yml). The sources come in at run time, see
# build-android.ps1; this image only holds the tools.
FROM ubuntu:24.04

ARG NDK_VERSION=r28c
ARG RUST_VERSION=1.75
ARG CARGO_NDK_VERSION=3.1.2
ARG FLUTTER_VERSION=3.24.5
ARG VCPKG_COMMIT_ID=9e593bb18ea69cc5095e012465dcd675a822ed0d
ARG CMDLINE_TOOLS=11076708

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake ca-certificates clang cmake curl g++ g++-multilib gcc-multilib git \
      libc6-dev libclang-dev libtool llvm-dev make nasm ninja-build openjdk-17-jdk-headless \
      pkg-config python3 tar unzip wget xz-utils zip \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Android NDK (for the Rust library and the vcpkg dependencies)
RUN wget -q https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip -O /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt && rm /tmp/ndk.zip
ENV ANDROID_NDK_HOME=/opt/android-ndk-${NDK_VERSION} \
    ANDROID_NDK_ROOT=/opt/android-ndk-${NDK_VERSION}

# Android SDK (for Gradle)
ENV ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip -O /tmp/cl.zip \
    && unzip -q /tmp/cl.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && rm /tmp/cl.zip \
    && yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null \
    && $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-36" "build-tools;35.0.0" > /dev/null

# Rust + cargo-ndk
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
ENV PATH=/opt/cargo/bin:/opt/flutter/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain ${RUST_VERSION} --component rustfmt \
    && rustup target add aarch64-linux-android armv7-linux-androideabi \
    && cargo install cargo-ndk --version ${CARGO_NDK_VERSION} --locked

# Flutter (the DareMoto patch is applied at build time, from the sources)
RUN git clone -q --depth 1 -b ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter \
    && git config --global --add safe.directory '*' \
    && flutter config --no-analytics > /dev/null && flutter --disable-analytics > /dev/null \
    && flutter precache --android > /dev/null

# vcpkg at the commit of the workflow
RUN git clone -q https://github.com/microsoft/vcpkg /opt/vcpkg \
    && git -C /opt/vcpkg checkout -q ${VCPKG_COMMIT_ID} \
    && /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics
ENV VCPKG_ROOT=/opt/vcpkg VCPKG_DEFAULT_BINARY_CACHE=/cache/vcpkg-bin

# host-side build scripts of some crates (openssl-sys), preinstalled on the GitHub runner
RUN apt-get update && apt-get install -y --no-install-recommends libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY build.sh /usr/local/bin/daremoto-build-android
RUN sed -i 's/\r$//' /usr/local/bin/daremoto-build-android && chmod +x /usr/local/bin/daremoto-build-android
