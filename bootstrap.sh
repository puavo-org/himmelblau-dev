#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

REQUIRED=(
  "ENABLE_HELLO"
  "HSM_TYPE"
  "TENANT_DOMAIN"
  "TENANT_ID"
)

for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "'$var' is not defined" >&2
    exit 1
  fi
done

OVMF_CODE_SRC="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS_SRC="/usr/share/OVMF/OVMF_VARS.fd"

for cmd in curl qemu-img parted mkfs.fat mkfs.ext4 debootstrap getopt jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "'$cmd' not found" >&2
    exit 1
  fi
done

ARG_UPDATE=0
ARG_CONFIG="himmelblau.conf.in"

if ! opts=$(getopt -o uc: --long update,config: -n "$(basename "$0")" -- "$@"); then
  echo "Invalid options" >&2
  exit 1
fi
eval set -- "$opts"
while true; do
  case "$1" in
  -u | --update)
    ARG_UPDATE=1
    shift
    ;;
  -c | --config)
    ARG_CONFIG="$2"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  esac
done

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") [-u|--update] [--config <file>] <output>" >&2
  exit 1
fi

BUILD_DIR=$1
mkdir -p "$BUILD_DIR"

BUILD_IMAGE_PATH="$BUILD_DIR/himmelblau-demo.qcow2"

if [ "$ARG_UPDATE" -eq 1 ]; then
  url="https://api.github.com/repos/himmelblau-idm/himmelblau/releases/latest"
  version=$(curl -sSf "$url" | jq -r '.tag_name')

  if [ -z "$version" ] || [ "$version" = "null" ]; then
    echo "Fetching Himmelblau version failed" >&2
    echo "Skipping Himmelblau version update" >&2
    exit 1
  fi
  echo "$version" >"himmelblau.version"
fi

teardown() {
  sudo umount /mnt 2>/dev/null || true
  sudo qemu-nbd -d /dev/nbd0 2>/dev/null || true
}

trap teardown EXIT INT TERM

if [ ! -d "$BUILD_DIR" ]; then
  echo "\"$BUILD_DIR\" is not a directory" >&2
  exit 1
fi

if [ ! -f "$ARG_CONFIG" ]; then
  echo "'$ARG_CONFIG' not found" >&2
  exit 1
fi

normalize_bool() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON|y|Y) echo "true" ;;
    0|false|FALSE|False|no|NO|off|OFF|n|N) echo "false" ;;
    *) echo "false" ;;
  esac
}

ENABLE_HELLO_BOOL=$(normalize_bool "$ENABLE_HELLO")
APPLY_POLICY_BOOL=$(normalize_bool "${APPLY_POLICY:-true}")

rendered_conf=$(
  jq -n -r \
    --arg content "$(<"$ARG_CONFIG")" \
    --arg domains "$TENANT_DOMAIN" \
    --arg hsm "$HSM_TYPE" \
    --arg enable "$ENABLE_HELLO_BOOL" \
    --arg apply "$APPLY_POLICY_BOOL" '
      $content
      | gsub("\\{\\{domains\\}\\}"; $domains)
      | gsub("\\{\\{hsm_type\\}\\}"; $hsm)
      | gsub("\\{\\{enable_hello\\}\\}"; $enable)
      | gsub("\\{\\{apply_policy\\}\\}"; $apply)
    '
)

if echo "$rendered_conf" | grep -q '{{[^}]*}}'; then
  echo "Unresolved placeholders remain in rendered configuration" >&2
  exit 1
fi

printf "%s" "$rendered_conf" > "$BUILD_DIR/himmelblau.conf"

if [ ! -f "$OVMF_CODE_SRC" ] || [ ! -f "$OVMF_VARS_SRC" ]; then
  echo "OVMF firmware files not found." >&2
  exit 1
fi

cp "$OVMF_CODE_SRC" "$BUILD_DIR/OVMF_CODE.fd"
cp "$OVMF_VARS_SRC" "$BUILD_DIR/OVMF_VARS.fd.template"

# Per-build SWTPM CA + configuration
SWTPM_CA_DIR="$BUILD_DIR/swtpm-ca"
mkdir -p "$SWTPM_CA_DIR"

# swtpm-localca.conf — local CA material stored under $BUILD_DIR/swtpm-ca
cat >"$SWTPM_CA_DIR/swtpm-localca.conf" <<EOF
statedir = $SWTPM_CA_DIR
signingkey = $SWTPM_CA_DIR/issuer_key.pem
issuercert = $SWTPM_CA_DIR/issuer_cert.pem
certserial = $SWTPM_CA_DIR/serial
issuercert_subject = CN=Opinsys Demo SWTPM CA
expiration = 3650
EOF

# swtpm_setup.conf — drive swtpm_setup to use swtpm_localca
cat >"$SWTPM_CA_DIR/swtpm_setup.conf" <<'EOF'
create_certs_tool = swtpm_localca
create_ek_cert = yes
create_platform_cert = no
lock_nvram = yes
EOF

# libtpms.conf — Infineon SLB9670-ish capabilities
cat >"$SWTPM_CA_DIR/libtpms.conf" <<'EOF'
TPM2Algorithms = sha1,sha256,aes,rsa,ecc
TPM2_RSA_KEY_SIZES = 2048
TPM2_ECC_CURVES = NIST_P256
TPM2_SYM_MODES = AES_128_CFB
TPM2_PCR_BANKS = sha1,sha256
TPM2AlgorithmsEx = sm3,sm4,camellia,des,tdes
TPM2Features = OwnerAuth,EndorsementAuth,LockoutAuth
EOF

qemu-img create -f qcow2 "$BUILD_IMAGE_PATH" 50G

sudo qemu-nbd -c /dev/nbd0 "$BUILD_IMAGE_PATH"

sudo parted -s -a optimal -- /dev/nbd0 \
  mklabel gpt \
  mkpart primary fat32 1MiB 512MiB \
  mkpart primary ext4 512MiB -0 \
  name 1 EFI \
  name 2 root \
  set 1 esp on

sudo partprobe /dev/nbd0

sudo mkfs.fat -F 32 -n EFI /dev/nbd0p1
sudo mkfs.ext4 -L root /dev/nbd0p2

sudo mount /dev/nbd0p2 /mnt

sudo debootstrap \
  --arch=amd64 \
  --include="apt-utils,console-setup,curl,iproute2,iputils-ping,jq,less,locales,lsb-release,sudo,systemd,systemd-sysv,tzdata,udhcpc,zstd,ca-certificates" \
  --components=main,contrib,non-free,non-free-firmware \
  --variant=minbase \
  bookworm /mnt http://deb.debian.org/debian/

sudo umount /mnt
sudo qemu-nbd -d /dev/nbd0
