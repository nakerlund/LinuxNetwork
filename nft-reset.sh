#!/usr/bin/env sh
set -eu

[ -f log/nftables.conf ] && nft -f log/nftables.conf || echo "No original values saved"