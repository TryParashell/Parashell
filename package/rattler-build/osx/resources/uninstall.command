#!/bin/sh
set -eu

auth_dir="$HOME/Library/Application Support/PARA"

if [ -d "$auth_dir" ]; then
    rm -rf "$auth_dir"
    echo "Removed Parashell auth directory: $auth_dir"
else
    echo "Parashell auth directory not found: $auth_dir"
fi
