#!/usr/bin/env sh
set -eu

if ping -c1 -W1 google.com >/dev/null 2>&1
then
  echo 'Ping already working'; 
else
  DNS_SERVER="$(grep -m1 '^nameserver' /etc/resolv.conf | grep -oE '\S+$' || true)"
  [ -z "${DNS_SERVER:-}" ] && DNS_SERVER=127.0.0.11
  echo "DNS_SERVER=$DNS_SERVER"

  # Check Docker NAT still exists (if this fails, rebuild the Dev Container)
  nft list table ip nat >/dev/null 2>&1 || {
    echo "Docker NAT (table ip nat) missing. Rebuild Dev Container (Rebuild & Reopen)."; exit 1; }

  nft insert rule ip filter output meta skuid $UID ip daddr $DNS_SERVER udp dport 53 accept
  # nft insert rule ip filter output meta skuid $UID ip daddr $DNS_SERVER tcp dport 53 accept

  # Allow ping requests
  nft add rule inet filter output icmp type echo-request accept

  # Quick exit if already ok
  if ! ping -c1 -W1 google.com >/dev/null 2>&1
  then
    echo 'Failed to restore ping'; 
  fi
fi

if ! ping -c1 -W1 mosquitto >/dev/null 2>&1
then
  echo 'Could not ping mosquitto'
  exit 0
fi

# Try Docker DNS first
BROKER_IP="$(getent hosts mosquitto 2>/dev/null | grep -m1 -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"

# Fallback: derive from eth0 (dev is usually .2, mosquitto .3)
if [ -z "${BROKER_IP:-}" ]; then
  ETH_IP="$(ip -4 addr show dev eth0 | grep -m1 -oE 'inet ([0-9]+\.){3}[0-9]+' | grep -oE '([0-9]+\.){3}[0-9]+')"
  NET_PREFIX="$(echo "$ETH_IP" | cut -d. -f1-3)"
  BROKER_IP="${NET_PREFIX}.3"
  grep -qE "^[[:space:]]*$BROKER_IP[[:space:]]+mosquitto(\s|$)" /etc/hosts 2>/dev/null || \
    echo "$BROKER_IP mosquitto" >> /etc/hosts
fi
echo "BROKER_IP=$BROKER_IP"

# Minimal allows: ICMP + MQTT/TLS (8883) to/from broker
nft add rule inet filter output ip daddr "$BROKER_IP" icmp type echo-request accept
nft add rule inet filter input  ip saddr "$BROKER_IP" icmp type echo-reply  accept
nft add rule inet filter output ip daddr "$BROKER_IP" tcp dport 8883 accept
nft add rule inet filter input  ip saddr "$BROKER_IP" tcp sport 8883 accept
