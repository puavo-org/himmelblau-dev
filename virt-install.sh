#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if ! command -v virt-install >/dev/null 2>&1; then
  echo "'virt-install' not found (install 'virtinst')." >&2
  exit 1
fi

if ! command -v virsh >/dev/null 2>&1; then
  echo "'virsh' not found (install 'libvirt-clients')." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "'python3' not found (install 'python3')." >&2
  exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <build_dir>" >&2
  exit 1
fi

BUILD_DIR=$1

if [ ! -d "$BUILD_DIR" ]; then
  echo "'$BUILD_DIR' is not a directory" >&2
  exit 1
fi

BUILD_DIR=$(cd "$BUILD_DIR" && pwd)

IMAGE="$BUILD_DIR/himmelblau-demo.qcow2"
OVMF_CODE="$BUILD_DIR/OVMF_CODE.fd"
OVMF_VARS_TEMPLATE="$BUILD_DIR/OVMF_VARS.fd.template"
OVMF_VARS="$BUILD_DIR/OVMF_VARS.fd"
XML_PATH="$BUILD_DIR/himmelblau-demo.xml"
DOMAIN_NAME="himmelblau-demo"
LIBVIRT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

if [ ! -f "$IMAGE" ]; then
  echo "'$IMAGE' not found; run 'make build' first." >&2
  exit 1
fi

if [ ! -f "$OVMF_CODE" ]; then
  echo "'$OVMF_CODE' not found; run 'make build' first." >&2
  exit 1
fi

if [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
  echo "'$OVMF_VARS_TEMPLATE' not found; run 'make build' first." >&2
  exit 1
fi

if [ ! -f "$OVMF_VARS" ]; then
  cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
fi

VIRT_INSTALL="${VIRT_INSTALL:-virt-install}"
VIRSH="${VIRSH:-virsh}"

"$VIRT_INSTALL" \
  --connect "$LIBVIRT_URI" \
  --name "$DOMAIN_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --cpu host-passthrough \
  --import \
  --disk "path=$IMAGE,format=qcow2,bus=virtio" \
  --os-variant debian12 \
  --boot "loader=$OVMF_CODE,loader.readonly=yes,loader.type=pflash,nvram=$OVMF_VARS" \
  --graphics "spice,listen=none" \
  --video qxl \
  --tpm "backend.type=emulator,backend.version=2.0,model=tpm-tis" \
  --network "user,model=virtio" \
  --noautoconsole \
  --print-xml > "$XML_PATH"

python3 - "$XML_PATH" <<'EOF'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit(1)

xml_path = Path(sys.argv[1])
tree = ET.parse(xml_path)
root = tree.getroot()

devices = root.find("devices")
if devices is not None:
    # Drop qemu-guest-agent channel that current host libvirt/qemu does not like
    channels_to_remove = []
    for ch in devices.findall("channel"):
        target = ch.find("target")
        if target is not None and target.get("name") == "org.qemu.guest_agent.0":
            channels_to_remove.append(ch)
    for ch in channels_to_remove:
        devices.remove(ch)

    # Configure user-mode networking for passt with SSH port forward
    iface = None
    for candidate in devices.findall("interface"):
        if candidate.get("type") == "user":
            iface = candidate
            break

    if iface is not None:
        has_backend = any(child.tag == "backend" for child in iface)
        if not has_backend:
            backend = ET.Element("backend", {"type": "passt"})
            children = list(iface)
            insert_index = 0
            for index, child in enumerate(children):
                if child.tag == "mac":
                    insert_index = index + 1
                    break
            iface.insert(insert_index, backend)

        has_tcp_pf = any(
            child.tag == "portForward" and child.get("proto") == "tcp"
            for child in iface
        )
        if not has_tcp_pf:
            port_forward = ET.Element("portForward", {"proto": "tcp"})
            ET.SubElement(port_forward, "range", {"start": "10022", "to": "22"})
            children = list(iface)
            insert_index = len(children)
            for index, child in enumerate(children):
                if child.tag == "backend":
                    insert_index = index + 1
            iface.insert(insert_index, port_forward)

    # Enforce 3D acceleration for the virtio video device
    video = devices.find("video")
    if video is not None:
        model = video.find("model")
        if model is not None and model.get("type") == "virtio":
            accel = model.find("acceleration")
            if accel is None:
                accel = ET.SubElement(model, "acceleration")
            accel.set("accel3d", "yes")

tree.write(xml_path, encoding="utf-8", xml_declaration=True)
EOF

"$VIRSH" -c "$LIBVIRT_URI" define "$XML_PATH" >/dev/null
