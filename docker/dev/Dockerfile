# Reproducible Linux development environment for «Поколение».
# The image contains toolchains, not the app source. The repository is bind-mounted
# at /workspace when the container starts.
FROM python:3.12-slim-bookworm

ARG FLUTTER_VERSION=3.47.9
ARG FLUTTER_SHA256=25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a
ARG ANDROID_TOOLS_BUILD=13114758
ARG ANDROID_TOOLS_SHA256=7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee
ARG JDK27_SHA256=d41bdc29a13920e90ee0f8e97a5bb9cb854ac06e0aa648a7fda1620db6c4e1ee

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_ROOT=/opt/flutter \
    JAVA_HOME=/opt/java \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PUB_CACHE=/home/dev/.pub-cache \
    GRADLE_USER_HOME=/home/dev/.gradle \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true \
    PATH=/opt/flutter/bin:/opt/java/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      clang \
      cmake \
      curl \
      file \
      git \
      lib32stdc++6 \
      lib32z1 \
      libglu1-mesa \
      libgtk-3-dev \
      liblzma-dev \
      libstdc++6 \
      ninja-build \
      pkg-config \
      unzip \
      xz-utils \
      zip \
    && rm -rf /var/lib/apt/lists/*

# Oracle JDK 27. The fixed checksum deliberately makes an upstream update fail
# closed; update the checksum in this Dockerfile when intentionally upgrading JDK 27.
RUN set -eux; \
    curl -fsSL "https://download.oracle.com/java/27/latest/jdk-27_linux-x64_bin.tar.gz" -o /tmp/jdk27.tar.gz; \
    echo "${JDK27_SHA256}  /tmp/jdk27.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/java; \
    tar -xzf /tmp/jdk27.tar.gz --strip-components=1 -C /opt/java; \
    rm -f /tmp/jdk27.tar.gz

# Flutter 3.47.9 includes Dart 3.13.7. Verify the SDK archive before extraction.
RUN set -eux; \
    curl -fL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz; \
    echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/flutter.tar.xz -C /opt; \
    rm -f /tmp/flutter.tar.xz

# Android SDK command-line tools 19.0 (build 13114758). Platform packages and
# Android licenses are intentionally NOT pre-accepted in the image.
RUN set -eux; \
    curl -fL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_TOOLS_BUILD}_latest.zip" -o /tmp/android-tools.zip; \
    echo "${ANDROID_TOOLS_SHA256}  /tmp/android-tools.zip" | sha256sum -c -; \
    mkdir -p /opt/android-sdk/cmdline-tools/latest; \
    unzip -q /tmp/android-tools.zip -d /tmp/android-tools; \
    cp -a /tmp/android-tools/cmdline-tools/. /opt/android-sdk/cmdline-tools/latest/; \
    rm -rf /tmp/android-tools /tmp/android-tools.zip

# The backend's Python dependencies are part of the image. Source files remain
# on the host and are mounted at runtime.
COPY backend/requirements.txt /tmp/backend-requirements.txt
RUN python -m pip install --no-cache-dir --disable-pip-version-check -r /tmp/backend-requirements.txt \
    && rm -f /tmp/backend-requirements.txt

RUN groupadd --gid 1000 dev \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash dev \
    && mkdir -p /home/dev/.pub-cache /home/dev/.gradle /opt/android-sdk \
    && chown -R dev:dev /opt/flutter /opt/java /opt/android-sdk /home/dev

USER dev
WORKDIR /workspace

RUN git config --global --add safe.directory /workspace \
    && flutter config --no-analytics \
    && flutter --version \
    && java -version \
    && dart --version \
    && python --version

CMD ["bash"]
