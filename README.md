# Linux - Felsökning av nätverk

I denna guide så har mycket strikta regler för trafik skapats av [nft-setup.sh](nftables.sh) som använder [nftables](https://wiki.archlinux.org/title/Nftables). Målet är inte bara att analysera och fixa anslutningen utan även att analysera MQTT keep alives paket med [WireShark](https://www.wireshark.org).

Projektet körs i en [Dev Container](.devcontainer/devcontainer.json) som baseras på [Docker-Compose](.devcontainer/docker-compose.yml) med en Ubuntu baserad [Dockerfile](.devcontainer/devcontainer.json) och MQTT brokern [Mosquitto](https://mosquitto.org).

För att enkelt verifera anslutningen så finns även en [MQTT klient](client.py) skriven i python. mTLS används och certifikat är skapade av [generate_certs.sh] som används av både av Mosquitto och klienten.

## 1. Kom igång med projektet

- Klona projektet med VS Code från [LinuxNetwork](https://github.com/nakerlund/LinuxNetwork)
- Tillåt VS Code att starta Dev Containern eller tryck `F1`, `> Dev Containers: Rebuild and Reopen in Container`
- Kolla loggarna så att Docker funkar.
- Öppna bash terminalen i Ubuntu som körs av Containern: `Ctrl + Shift + ö`

## 2. Testa ansluta klienten

Kör MQTT klienten: `python3 client.py`

Det ska inte fungera. Avbrut med: `Ctrl + C`

Se om nätverksenheten har hittats: `ip link show`

`eth0` är anslutningen och ska ha hittats.

Verifera att den hara en ip adress: `ip -4 addr show dev eth0`

Svaret bör vara något i stil med:

```sh
285: eth0@if286: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default  link-netnsid 0
    inet 172.19.0.3/16 brd 172.19.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```
`172.19.0.3` är ip adressen och med `/16` är det en [CIDR](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing) som anger nätmasken. De första 16 bitarna är nätverksdelen, vilket ger ett subnät som kan innehålla adresser från `172.19.0.1` till `172.19.255.255`.

Allt är som det ska med hårdvaran.

## 3. Använd tmux för bättre överblick för vidare felsökning

Öppan tmux för att felsöka effektivt

Kör: `tmux`

Tryck `Crtl + B, %` för att dela fönstret i två

Sätt igång tcpdump för ping: `tcpdump -n icmp or udp`

Hoppa till vänstra fönstret med: `Ctrl + B, ←`

Testa ping för att se om anslutningen fungerar: `ping google.com`

Vilket bör ge svaret: `ping: google.com: Temporary failure in name resolution`

## 3. DNS fel

Kolla om DNS server finns konfigurerad: `cat /etc/resolv.conf`

`nameserver` borde finnas med i svaret.

Använda nft för att tillåta DNS trafik:

```bash
# Tillåt utgående DNS-trafik
nft add rule inet filter output udp dport 53 accept
# Tillåt inkommande DNS-svar
nft add rule inet filter input udp sport 53 accept
```

Testa om det fungerade: `ping google.com`
Nu bör DNS namnet hittas men ingen data överföras. Hur ser det ut i högra tmux fönstret?

Avbryt ping med: `Ctrl + C`

## 4. Tillåt även ping

Skapa en regler för att tillåta ping med nft:

```bash
# Tillåt utgående ICMP (för ping)
nft add rule inet filter output icmp type echo-request accept
# Tillåt inkommande ICMP-svar
nft add rule inet filter input icmp type echo-reply accept
```

Testa igen: `ping google.com`

Nu bör anslutningen fungera och nätverkspaketen visas av tcpdump

Avbryt med: `Ctrl + C`

## 5. Använd traceroute

Kolla hur anslutningen till google ser ut: `traceroute google.com`

Regler behövs:

```bash
# Tillåt utgående UDP för traceroute (använder höga portar, ofta 33434-33534)
nft add rule inet filter output udp dport 33434-33534 accept

# Tillåt inkommande ICMP time-exceeded (typ 11) som routrarna skickar tillbaka
nft add rule inet filter input icmp type time-exceeded accept

# Tillåt även destination unreachable (typ 3) för när vi når målet
nft add rule inet filter input icmp type destination-unreachable accept

# Tillåt utgående TCP SYN paket för traceroute
nft add rule inet filter output tcp flags syn accept

# Tillåt inkommande TCP RST paket
nft add rule inet filter input tcp flags rst accept

# Tillåt inkommande TCP RST+ACK paket
nft add rule inet filter input tcp flags rst,ack accept

# För ICMP traceroute
nft add rule inet filter input icmp type time-exceeded accept
```

Testa igen: `traceroute google.com`

Prova också med ICMP-baserad traceroute: `traceroute -I google.com`

Och med TCP SYN-paket som ibland kommer igenom brandväggar bättre: `traceroute -T google.com`

## 6. Hitta MQTT brokern och port

Scanna lokala nätverket: `arp-scan --localnet`

När `172.19.0.3` hittats går det fint att avbryta: `Ctrl + C`

Se om det finns en väg: `traceroute 172.19.0.3`

Testa pinga: `ping 172.19.0.3`

Hämta dns namn: `nslookup 172.19.0.3`

Prova även `dig` för dns namn: `dig -x 172.19.0.3 +short`

Testa pinga med namnet: `ping linuxnetwork_devcontainer-mosquitto-1.linuxnetwork_devcontainer_default.`

Se om port 8883 för MQTTS är öppen: `nmap -p 8883 172.19.0.3`

Det gick inte. Tillåt med nft:

```bash
# Tillåt utgående TCP för nmap
nft add rule inet filter output tcp flags syn accept

# Tillåt inkommande svar
nft add rule inet filter input tcp flags syn,ack accept
```

Se om port 8883 för MQTTS är öppen: `nmap -p 8883 172.19.0.3`

## 7. Testa ansluta med klienten

När vi nu vet vad vi ska ansluta till kan vi skapa en mycket specifik regel:

```bash
# Tillåt TCP anslutningar till 172.19.0.3:8883 
nft add rule inet filter output ip daddr 172.19.0.3 tcp dport 8883 accept
# Tillåt TCP inkommande
nft add rule inet filter input ip saddr 172.19.0.3 accept
```

Kör: `python3 client.py`

Funkar det?

Avsluta med: `Ctrl + C`

## 8. Skapa log för Wireshark

Hoppa till högra tmux fönstret: `Ctrl + B, >`

Avsluta pågående tcpdump: `Ctrl + C`

Kör tcpdump med loggning till fil för Wireshark: `tcpdump -i eth0 host linuxnetwork_devcontainer-mosquitto-1.linuxnetwork_devcontainer_default and tcp port 8883 -w log/$(date +"%Y-%m-%d_%H-%M-%S").pcap`

Hoppa till vänstra tmux fönstret igen: `Ctrl + B, <`

Kör klienten för att fånga trafiken: `python3 client.py`

Vänta ett par minuter för att keep-alives ska skickas och fångas av loggen.

Avsluta klienten: `Ctrl + C`

Stäng shellet: `exit`

Avsluta tcpdump: `Ctrl + C`

Stäng shellet: `exit`

## 9. Wireshark

- Starta Wireshark.
- Öppna pcap loggfilen i wireshark.
- Använd även senaste sslkeylog som tillhör pcap logfilen.

Kolla hur ofta keepalives skickades.

Gick det att dekrpytera trafiken med sslkeylog filen?
