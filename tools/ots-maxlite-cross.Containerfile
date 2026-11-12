# ots maxlite cross-build environment: Debian 12 with aarch64 and armhf (32-bit ARM) cross
# compilers and the target Xerces-C and OpenSSL development packages (Debian multiarch).
FROM docker.io/library/debian:bookworm
# single-UID rootless podman cannot setgroups: keep apt from switching to its _apt user
RUN echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99no-sandbox && \
    dpkg --add-architecture arm64 && dpkg --add-architecture armhf && apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential g++-aarch64-linux-gnu g++-arm-linux-gnueabihf \
      git curl wget ca-certificates make gettext-base psmisc rsync python3 file binutils \
      libxerces-c-dev libssl-dev \
      libxerces-c-dev:arm64 libssl-dev:arm64 \
      libxerces-c-dev:armhf libssl-dev:armhf && \
    rm -rf /var/lib/apt/lists/*
