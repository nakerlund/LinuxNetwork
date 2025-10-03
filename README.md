# Linux - Felsökning av nätverk

I denna guide så har mycket strikta regler för trafik skapats av [nft-setup.sh](nft-setup.sh) som använder [nftables](https://wiki.archlinux.org/title/Nftables). Målet är inte bara att analysera och fixa anslutningen utan även att analysera MQTT paket med [WireShark](https://www.wireshark.org).

Projektet körs i en [Dev Container](.devcontainer/devcontainer.json) som baseras på [Docker-Compose](.devcontainer/docker-compose.yml) med en Ubuntu baserad [Dockerfile](.devcontainer/Dockerfile) och MQTT brokern [Mosquitto](https://mosquitto.org).

För att enkelt verifera anslutningen så finns även en [MQTT klient](client.py) skriven i python. mTLS används och certifikat är skapade av [generate_certs.sh](generate_certs.sh) som används av både av Mosquitto och klienten.

## 1. Kom igång med projektet

- Öppna VS Code och tryck `CTRL + SHIFT + P` för att öppna kommandopaletten.
- Clona projectet `Git: Clone`, `Clone from GitHub`, "[Nakerlund/LinuxNetwork](https://github.com/nakerlund/LinuxNetwork)"
- Tillåt VS Code att starta Dev Containern eller tryck `CTRL + SHIFT + P`, `> Dev Containers: Rebuild and Reopen in Container`
- Kolla loggarna så att Docker funkar undersök annars i Docker Desktop.
- I VS Code, öppna bash terminalen: `CTRL + SHIFT + Ö`

> Tips: Anslutningar och dev containers hanteras i VS Code nere i vänstra hörnet.
> [nft-setup.sh](nft-setup.sh) Återställer övningen. Det går även fint att bygga om containern i VS Code.
> [nft-reset.sh](nft-reset.sh) Rensar alla tillagda regler i `nftables`.
> [nft-cheat.sh](nft-cheat.sh) Skapar regler för att tillåta klienten att ansluta till brokern. Då kan man hoppa över felsökningen och skippa till steg 8.
> `nft list ruleset` visar reglerna som finns. De första är skapade av docker och behövs för att systemet ska verka som en vanlig linux.

## 2. Testa ansluta klienten

- Kör MQTT klienten: `python3 client.py`

Det ska inte fungera och måste i så fall felsökas

- Se om nätverksenheten har hittats: `ip link show`

`eth0` är NIC:en (**N**etwork **I**nterface **C**ontroller) och ska finnas.

- Verifera att eth0 är igång och har en IP adress: `ip -4 addr show dev eth0`

Svaret bör vara något i stil med:

```sh
285: eth0@if286: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default  link-netnsid 0
    inet 172.19.0.3/16 brd 172.19.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```

`172.19.0.3` eller liknande är IP adressen och `/16` är en [CIDR](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing) som anger nätmasken. De första 16 bitarna är nätverksdelen, vilket ger ett subnät som kan innehålla adresser från `172.19.0.1` till `172.19.255.255`.

- Allt är som det ska med eth0. Vi sparar egna IP adressen i en variabel för senare:

```bash
MY_IP=$(ip -o addr show dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "My IP: $MY_IP"
```

## 3. Använd tmux för bättre överblick för vidare felsökning

- Öppan `tmux` för att felsöka effektivt: `tmux`

- Tryck `CTRL + B, %` för att dela fönstret i två

- Sätt igång `tcpdump` för att se vad som händer: `tcpdump -i eth0 -v -x`

- Hoppa till vänstra fönstret med: `CTRL + B, ←`

- Testa ping för att se om anslutningen fungerar: `ping google.com`

Svaret `ping: google.com: Temporary failure in name resolution` betyder att DNS (**D**omain **N**ame **S**ystem) inte fungerar.

## 4. DNS fel

- Kolla om DNS server `nameserver` finns konfigurerad: `cat /etc/resolv.conf`

- Sätt en variabel med DNS-servern

```bash
DNS_SERVER=$(grep -m1 '^nameserver' /etc/resolv.conf | grep -oE '\S+$')
echo "DNS server: $DNS_SERVER"
```

Använda `nft` för att tillåta namnuppslag:

```bash
  nft insert rule ip filter output meta skuid $UID ip daddr $DNS_SERVER udp dport 53 accept
```

`$UID` är en variabel med användarens id som redan finns i terminalen.
Annars kan användas `id -u` för att hitta användarens id.

- Testa om det fungerade: `ping google.com`

Nu bör DNS namnet hittas men ingen data överföras. Hur ser det ut i högra `tmux` fönstret?

- Avbryt ping med: `CTRL + C`

## 5. Tillåt även ping

- Skapa en regel för att tillåta ping: `nft add rule inet filter output icmp type echo-request accept`

- Testa igen: `ping google.com`

Nu bör anslutningen fungera och nätverkspaketen visas av tcpdump

- Avbryt med: `CTRL + C`

## 6. Använd traceroute

- Kolla hur anslutningen till Google ser ut: `traceroute google.com`

- Regler behövs:

```bash
# Tillåt utgående UDP för traceroute (använder höga portar, ofta 33434-33534)
nft add rule inet filter output udp dport 33434-33534 accept

# Tillåt inkommande ICMP time-exceeded (typ 11) som routrarna skickar tillbaka
nft add rule inet filter input icmp type time-exceeded accept

# Tillåt även destination unreachable (typ 3) för när vi når målet
nft add rule inet filter input icmp type destination-unreachable accept

# Tillåt utgående TCP SYN paket för traceroute
nft add rule inet filter output tcp flags syn accept

# Tillåt inkommande TCP RST+ACK paket
nft add rule inet filter input tcp flags rst,ack accept

# För ICMP traceroute
nft add rule inet filter input icmp type time-exceeded accept
```

Beroende på verktyg i VS Code så kan även annan trafik visas av tcpdump.

- Testa igen: `traceroute google.com`

Varje rad är en "hop" som visar varje router på vägen till målet. Ofta bara `* * *` vilket betyder att routern inte svarade på en ICMP förfrågan. Den skickar anonymt vidare paketet.

## 7. Hitta MQTT brokern och port

- Scanna lokala nätverket: `arp-scan --localnet`

Den första IP adressen är ofta gateway routern och slutar ofta på `.1` och är inte MQTT brokern.

När en ip hittats som inte är den egna går det fint att avbryta: `CTRL + C`

- Definiera en variabel med ip adressen: `BROKER_IP=[hittad ip adress]`

- Se om det finns en väg: `traceroute $BROKER_IP`

- Testa pinga: `ping $BROKER_IP`

- Hämta DNS namn: `nslookup $BROKER_IP`

- Hämta DNS namn med `host`: `host $BROKER_IP`

- Hämta DNS namn med `getent`: `getent hosts $BROKER_IP`

- Prova även `dig`: `dig -x $BROKER_IP`

- Skapa en variabel med DNS namnet: `BROKER_NAME=$(dig -x $BROKER_IP +short)`

- Testa pinga med namnet: `ping $BROKER_NAME`

- Testa hämta IP med namnet: `getent hosts $BROKER_NAME`

- Test med `nslookup`: `nslookup $BROKER_NAME`

- Test med `host`: `host $BROKER_NAME`

- Se om port 8883 för MQTTS är öppen: `nmap -p 8883 $BROKER_IP`

## 8. Testa ansluta med klienten

- Skapa en mycket specifik regel för MQTTS till brokern: `nft add rule inet filter output ip daddr $BROKER_IP tcp dport 8883 accept`

- Kör MQTT klienten: `python3 client.py`

Det ska nu fungera och visa anslutning, publicering och mottagning av meddelande.

- Avsluta klienten med: `CTRL + C`

- Verifera att klienten kan ansluta: `python3 client.py`

- Avsluta klienten med: `CTRL + C`

## 9. Skapa log för Wireshark

- Hoppa till högra `tmux` fönstret: `CTRL + B, →`

- Avsluta pågående tcpdump: `CTRL + C`

- Kör tcpdump med loggning till fil för Wireshark: `tcpdump -i eth0 host linuxnetwork_devcontainer-mosquitto-1.linuxnetwork_devcontainer_default and tcp port 8883 -w log/$(date +"%Y-%m-%d_%H-%M-%S").pcap`

- Hoppa till vänstra `tmux` fönstret igen: `CTRL + B, ←`

- Kör klienten för att spela in trafiken: `python3 client.py`

När klienten skickat sitt meddelande kan du avsluta: `CTRL + C`

- Stäng shellet: `exit`

- Avsluta tcpdump: `CTRL + C`

- Stäng shellet: `exit`

## 10. Wireshark

- Starta Wireshark
- Öppna pcap loggfilen från mappen log/
- Använd även sslkeylog som tillhör pcap logfilen för TLS protokollet i Wireshark

Gick det att dekrpytera trafiken med sslkeylog filen i Wireshark?
