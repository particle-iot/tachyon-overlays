# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG OVERLAY_TOOL_REPO=https://github.com/particle-iot/tachyon-overlay-tool.git
# Pin the runtime instead of following a moving main branch.
ARG OVERLAY_TOOL_REF=99dca2ae2b87e82be1695c21d4c8cfa806b7e065

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        e2fsprogs \
        fdisk \
        file \
        git \
        mount \
        python3 \
        qemu-user-static \
        rsync \
        sudo \
        util-linux \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN git init /opt/tachyon-overlay-tool \
    && git -C /opt/tachyon-overlay-tool remote add origin "${OVERLAY_TOOL_REPO}" \
    && git -C /opt/tachyon-overlay-tool fetch --depth 1 origin "${OVERLAY_TOOL_REF}" \
    && git -C /opt/tachyon-overlay-tool checkout --detach FETCH_HEAD \
    && test -f /opt/tachyon-overlay-tool/overlay.py \
    && rm -rf /opt/tachyon-overlay-tool/.git

COPY scripts/apply-rootfs.sh /usr/local/bin/apply-rootfs
COPY scripts/install-kernel.sh /usr/local/bin/install-kernel
RUN chmod 0755 /usr/local/bin/apply-rootfs /usr/local/bin/install-kernel

ENTRYPOINT ["/usr/local/bin/apply-rootfs"]
