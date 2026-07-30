#!/usr/bin/env bash

set -euo pipefail

readonly pixi_version="0.68.0"
readonly pixi_archive_sha256="60e7f43b4087710a2f9a72efd421741f5ca6267c6a027197a19a1bc060516e99"

if [[ "$(pixi --version 2>/dev/null || true)" == "pixi ${pixi_version}" ]]; then
    exit 0
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "Unsupported sandbox platform: $(uname -s) $(uname -m)" >&2
    exit 1
fi

archive="$(mktemp)"
extract_dir="$(mktemp -d)"
cleanup() {
    rm -f "${archive}"
    rm -rf "${extract_dir}"
}
trap cleanup EXIT

curl -fL --retry 3 --retry-all-errors \
    -o "${archive}" \
    "https://github.com/prefix-dev/pixi/releases/download/v${pixi_version}/pixi-x86_64-unknown-linux-musl.tar.gz"
echo "${pixi_archive_sha256}  ${archive}" | sha256sum --check --status
tar -xzf "${archive}" -C "${extract_dir}"

if [[ -w /usr/local/bin ]]; then
    install -m 0755 "${extract_dir}/pixi" /usr/local/bin/pixi
else
    sudo install -m 0755 "${extract_dir}/pixi" /usr/local/bin/pixi
fi
