#!/usr/bin/env sh
set -eu

DNS_SERVER="$(grep -m1 '^nameserver' /etc/resolv.conf | grep -oE '\S+$' || true)"
[ -z "${DNS_SERVER:-}" ] && DNS_SERVER=127.0.0.11


if [ -f log/nftables.conf ]
then
    # Restore original values
    nft -f log/nftables.conf
else
    # Backup original values
    nft list ruleset > log/nftables.conf
fi

# Block dns lookups
nft add table ip filter
nft add chain ip filter output { type filter hook output priority -100\; policy accept\; }
nft add rule ip filter output ip daddr $DNS_SERVER udp dport 53 drop
nft add rule ip filter output ip daddr $DNS_SERVER tcp dport 53 drop

nft add table inet filter
nft add chain inet filter input { type filter hook input  priority filter\; policy drop\; }
nft add chain inet filter output { type filter hook output priority filter\; policy drop\; }

nft add rule  inet filter input  iifname "lo" accept
nft add rule  inet filter output oifname "lo" accept
nft add rule  inet filter input  ct state established,related accept
nft add rule  inet filter output ct state established,related accept