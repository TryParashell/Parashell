#!/bin/sh
set -eu

config_base="${XDG_CONFIG_HOME:-$HOME/.config}"
auth_dir="$config_base/PARA"

if [ -d "$auth_dir" ]; then
    rm -rf "$auth_dir"
    echo "Removed Parashell auth directory: $auth_dir"
else
    echo "Parashell auth directory not found: $auth_dir"
fi
