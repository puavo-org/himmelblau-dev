# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

FROM debian:12-slim

RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      debootstrap \
      fakechroot \
      fakeroot \
      ca-certificates \
      curl \
      xz-utils \
      gnupg; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY compose-helper.sh /compose-helper.sh
RUN chmod +x /compose-helper.sh
