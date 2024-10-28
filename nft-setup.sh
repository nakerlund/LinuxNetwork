#!/bin/sh

# Clear all existing rules
nft flush ruleset

# Create a new table and the base chains
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add chain inet filter forward { type filter hook forward priority 0 \; policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \; policy drop \; }

# Allow loopback traffic
nft add rule inet filter input iifname lo accept
nft add rule inet filter output oifname lo accept

# Allow docker0 interface traffic
nft add rule inet filter input iifname docker0 accept
nft add rule inet filter output oifname docker0 accept

# Allow DNS (both UDP and TCP)
# nft add rule inet filter output ip protocol {tcp,udp} th dport 53 accept
# nft add rule inet filter input ip protocol {tcp,udp} th sport 53 accept

# Allow ICMP for ping
# nft add rule inet filter output ip protocol icmp icmp type echo-request accept
# nft add rule inet filter input ip protocol icmp icmp type echo-reply accept

# List all rules to verify
nft list ruleset