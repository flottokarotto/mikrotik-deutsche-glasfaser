# MikroTik RouterOS - Deutsche Glasfaser Konfiguration

Optimierte MikroTik RouterOS 7.x Konfiguration für einen **Deutsche Glasfaser FTTH-Anschluss** (300/300 Mbit/s).

## Netzwerk-Layout

```
Deutsche Glasfaser ONT
        │
    ether1 (WAN, DHCP, CGNAT IPv4, SLAAC IPv6)
        │
   ┌────┴────┐
   │ MikroTik│
   │  hEX S  │
   └────┬────┘
        │
   ether2-4, sfp1 ──── LAN Bridge (192.168.42.0/24)
        │
   ether5 ──────────── Gastnetz (192.168.88.0/24, isoliert)
        │
   WireGuard ────────── VPN (192.168.89.0/24, Back-to-Home)
```

## Features

| Feature | Details |
|---------|---------|
| **Gastnetz** | Eigene Bridge auf ether5, komplett isoliert vom LAN, kein PoE |
| **DNS-over-HTTPS** | Cloudflare (1.1.1.1) mit Zertifikatspruefung |
| **SQM** | fq_codel auf 285/285 Mbit/s (Bufferbloat-Kontrolle) |
| **IGMP Snooping** | Multicast-Querier + IGMP Proxy (IPTV, Chromecast, Sonos) |
| **mDNS** | AirPlay, Chromecast, Drucker-Discovery im LAN |
| **UPnP** | Fuer Gaming und Streaming |
| **NTP Server** | Zeitserver fuer alle LAN-Geraete |
| **DHCP-to-DNS** | Geraete automatisch als `<hostname>.lan` erreichbar (Lease-Script direkt im DHCP-Server) |
| **IPv6** | SLAAC + ULA-Adressen + NAT Masquerade (DG liefert kein Prefix Delegation) |
| **VPN** | MikroTik Back-to-Home VPN (WireGuard, umgeht CGNAT) |
| **DynDNS** | MikroTik Cloud (ip cloud) |
| **Sicherheit** | Telnet/FTP/API deaktiviert, SSH+Winbox nur aus LAN/VPN |

## Deutsche Glasfaser Besonderheiten

- **CGNAT**: DG vergibt IPv4-Adressen aus dem `100.64.0.0/10` Bereich — kein Port-Forwarding moeglich
- **Kein Prefix Delegation**: IPv6 nur als einzelne `/128` per SLAAC, kein routebares Prefix
- **DoH**: Quad9 funktioniert nicht hinter DG CGNAT, Cloudflare (1.1.1.1) geht
- **VPN**: Klassisches Port-Forwarding unmoeglich wegen CGNAT — MikroTik Back-to-Home VPN als Loesung

## Installation

### 1. Backup erstellen

```routeros
/system backup save name=vor-optimierung
/export file=vor-optimierung
```

### 2. Konfiguration anpassen

- Subnetze, IP-Bereiche und Interface-Zuordnung nach Bedarf aendern
- MAC-Adressen (`XX:XX:XX:XX:XX:XX`) durch eigene ersetzen
- Statische DHCP-Leases fuer eigene Geraete anpassen

### 3. Importieren

```routeros
/import file-name=mikrotik-deutsche-glasfaser.rsc
```

### 4. CA-Zertifikate importieren (fuer DoH)

```routeros
# Device-Mode: fetch muss aktiviert sein
/system device-mode set fetch=yes
# (Reset-Knopf kurz druecken, Router startet neu)

# Danach:
/ip dns set use-doh-server="" servers=185.22.44.50
/tool fetch url=https://curl.se/ca/cacert.pem mode=https dst-path=cacert.pem
/certificate import file-name=cacert.pem passphrase=""
```

### 5. Back-to-Home VPN aktivieren

```routeros
/ip cloud set back-to-home-vpn=enabled ddns-enabled=yes
```

QR-Code fuer die WireGuard App wird automatisch generiert.

### 6. Pruefen

```routeros
:put [:resolve google.com]
/ip cloud print
/interface wireguard print
/queue simple print
/ip dns static print where comment="DHCP auto"
```

## SQM Tuning

Die Queue ist auf 95% der Leitungskapazitaet (285 Mbit/s) eingestellt. Testen mit:
- [Waveform Bufferbloat Test](https://www.waveform.com/tools/bufferbloat)
- [DSLReports Speed Test](http://www.dslreports.com/speedtest)

Falls Bandbreite zu stark beschnitten: `max-limit` auf `290M/290M` erhoehen.

## Lizenz

Public Domain — nutzen, anpassen, weitergeben wie gewuenscht.
