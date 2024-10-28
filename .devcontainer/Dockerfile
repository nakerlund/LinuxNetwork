FROM ubuntu:24.04

# Installera nödvändiga paket
RUN apt-get update && apt-get install -y \
    \
    # Python och MQTT
    python3 python3-paho-mqtt \
    \
    # Nätverksverktyg
    # Krypteringsverktyg
    openssl \
    # Printar ut nätverkstrafik
    tcpdump \
    # Hittat enher på nätverket
    arp-scan \
    # List öppna portar
    nmap \
    # Hittar domännamn 
    dnsutils \
    # Ping
    iputils-ping \
    # Traceroute, visar vägen till en server
    traceroute \
    # Netcat, skicka data över nätverket
    netcat-openbsd \
    # Iptables, inkluderar ntftables
    iptables \
    # iproute2, ip kommandot för att hantera nätverk
    iproute2 \
    # terminal multiplexer, för att köra flera terminaler i en
    tmux \
    \
    # Klart, rensa upp docker imagen så den inte tar upp onödig plats
    && rm -rf /var/lib/apt/lists/*