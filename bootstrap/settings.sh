#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

declare -gA CONFIG

settings_new() {
  CONFIG=(
    [debug]="true"
    [domains]=""
    [home_alias]="CN"
    [home_attr]="CN"
    [id_attr_map]="name"
    [pam_allow_groups]=""
    [use_etc_skel]="true"
    [local_groups]="users"
    [hsm_type]="soft"
    [enable_hello]="true"
  )
}

settings_load() {
  local config_file="$1"
  settings_new
  if [ -n "$config_file" ]; then
    if [ ! -f "$config_file" ]; then
      echo "'$config_file' not found." >&2
      exit 1
    fi
    echo "Loading '$config_file'"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^\s*# || -z "$line" ]] && continue

      key="${line%%=*}"
      value="${line#*=}"

      # Trim
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      if [ -n "$key" ]; then
        CONFIG["$key"]="$value"
      fi
    done <"$config_file"
  else
    echo "Loading environment variables"
    CONFIG[tenant_id]="${TENANT_ID:-}"
    CONFIG[tenant_domain]="${TENANT_DOMAIN:-}"
    CONFIG[hsm_type]="${HSM_TYPE:-${CONFIG[hsm_type]}}"
    CONFIG[enable_hello]="${ENABLE_HELLO:-${CONFIG[enable_hello]}}"
  fi
}

settings_check() {
  if [ -z "${CONFIG[tenant_id]}" ]; then
    echo "TENANT_ID is not set" >&2
    exit 1
  fi
  if [ -z "${CONFIG[tenant_domain]}" ]; then
    echo "TENANT_DOMAIN is not set" >&2
    exit 1
  fi
  CONFIG[domains]="${CONFIG[domains]:-${CONFIG[tenant_domain]}}"
  CONFIG[pam_allow_groups]="${CONFIG[pam_allow_groups]:-${CONFIG[tenant_id]}}"
}

settings_generate() {
  {
    echo "[global]"
    echo "debug = ${CONFIG[debug]}"
    echo "domains = ${CONFIG[domains]}"
    echo "home_alias = ${CONFIG[home_alias]}"
    echo "home_attr = ${CONFIG[home_attr]}"
    echo "id_attr_map = ${CONFIG[id_attr_map]}"
    echo "pam_allow_groups = ${CONFIG[pam_allow_groups]}"
    echo "use_etc_skel = ${CONFIG[use_etc_skel]}"
    echo "local_groups = ${CONFIG[local_groups]}"
    echo "hsm_type = ${CONFIG[hsm_type]}"
    echo "enable_hello = ${CONFIG[enable_hello]}"
  } >> "$1"
}
