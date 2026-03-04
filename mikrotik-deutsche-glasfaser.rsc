# ============================================================================
# MikroTik RouterOS 7.x - Optimierte Konfiguration fuer Deutsche Glasfaser
# ============================================================================
# Modell: hEX S (oder vergleichbar mit 5x Ethernet + SFP)
# Anschluss: Deutsche Glasfaser 300/300 Mbit/s (CGNAT IPv4, SLAAC IPv6)
#
# Netzwerk-Layout:
#   ether1        = WAN (Deutsche Glasfaser, DHCP, CGNAT)
#   ether2-4,sfp1 = LAN Bridge (192.168.42.0/24)
#   ether5        = Gastnetz (192.168.88.0/24, isoliert, kein PoE)
#   WireGuard     = Back-to-Home VPN (MikroTik Cloud, umgeht CGNAT)
#
# Features:
#   - DNS-over-HTTPS (Cloudflare)
#   - DHCP-to-DNS (Geraete als <hostname>.lan erreichbar)
#   - SQM/fq_codel Bufferbloat-Kontrolle
#   - IGMP Snooping + Multicast Proxy
#   - UPnP, mDNS
#   - IPv6 mit ULA + NAT Masquerade
#   - Gastnetz komplett isoliert
#   - Gehaertete Services
#
# DHCP-Lease-Script ist direkt im DHCP-Server integriert (DHCP-to-DNS)
# ============================================================================

# ---- Bridge + Gastnetz ----
/interface bridge
add admin-mac=XX:XX:XX:XX:XX:XX auto-mac=no comment=defconf igmp-snooping=yes multicast-querier=yes name=bridge
add comment=Gastnetz name=bridge-guest
/interface ethernet
set [ find default-name=ether5 ] poe-out=off

# ---- WireGuard VPN ----
/interface wireguard
add comment=back-to-home-vpn listen-port=30311 mtu=1420 name=back-to-home-vpn
add comment="WireGuard VPN (Port 443)" listen-port=443 mtu=1420 name=wireguard-vpn

# ---- Interface-Listen ----
/interface list
add comment=defconf name=WAN
add comment=defconf name=LAN
add comment=Gastnetz name=GUEST

# ---- IP Pools ----
/ip pool
add name=default-dhcp ranges=192.168.88.10-192.168.88.254
add name=dhcp ranges=192.168.42.20-192.168.42.200
add name=vpn ranges=192.168.89.2-192.168.89.255

# ---- DHCP Server (mit DHCP-to-DNS Lease Script) ----
/ip dhcp-server
add address-pool=dhcp interface=bridge lease-script=":if (\$leaseBound = 1) do\
    ={\
    \n    :if ([:len \$\"lease-hostname\"] > 0) do={\
    \n      :local fqdn (\$\"lease-hostname\" . \".lan\")\
    \n      :do {/ip dns static remove [find name=\$fqdn comment=\"DHCP auto\"\
    ]} on-error={}\
    \n      :do {/ip dns static add name=\$fqdn address=\$leaseActIP ttl=00:15:00 c\
    omment=\"DHCP auto\"} on-error={}\
    \n    }\
    \n  } else={\
    \n    :if ([:len \$\"lease-hostname\"] > 0) do={\
    \n      :local fqdn (\$\"lease-hostname\" . \".lan\")\
    \n      :do {/ip dns static remove [find name=\$fqdn comment=\"DHCP auto\"\
    ]} on-error={}\
    \n    }\
    \n  }" lease-time=12h name=defconf
add address-pool=default-dhcp comment="Gastnetz DHCP" interface=bridge-guest \
    lease-script=":if (\$leaseBound = 1) do={\
    \n    :if ([:len \$\"lease-hostname\"] > 0) do={\
    \n      :local fqdn (\$\"lease-hostname\" . \".lan\")\
    \n      :do {/ip dns static remove [find name=\$fqdn comment=\"DHCP auto\"\
    ]} on-error={}\
    \n      :do {/ip dns static add name=\$fqdn address=\$leaseActIP ttl=00:15:00 c\
    omment=\"DHCP auto\"} on-error={}\
    \n    }\
    \n  } else={\
    \n    :if ([:len \$\"lease-hostname\"] > 0) do={\
    \n      :local fqdn (\$\"lease-hostname\" . \".lan\")\
    \n      :do {/ip dns static remove [find name=\$fqdn comment=\"DHCP auto\"\
    ]} on-error={}\
    \n    }\
    \n  }\
    \n" lease-time=1h name=dhcp-guest

# ---- Queue Types + SQM (300 Mbit/s Anschluss) ----
/queue type
add fq-codel-limit=1024 fq-codel-quantum=300 kind=fq-codel name=fq-codel-download
add fq-codel-limit=1024 fq-codel-quantum=300 kind=fq-codel name=fq-codel-upload
/queue simple
add bucket-size=0.01/0.01 comment="SQM Bufferbloat-Kontrolle (DG 300 Mbit/s)" max-limit=285M/285M name=WAN-SQM queue=fq-codel-upload/fq-codel-download target=ether1

# ---- Disk/SMB ----
/disk settings
set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes

# ---- Bridge Ports ----
/interface bridge port
add bridge=bridge comment=defconf interface=ether2
add bridge=bridge comment=defconf interface=ether3
add bridge=bridge comment=defconf interface=ether4
add bridge=bridge comment=defconf interface=sfp1
add bridge=bridge-guest interface=ether5

# ---- Neighbor Discovery ----
/ip neighbor discovery-settings
set discover-interface-list=LAN

# ---- IPv6 Settings ----
/ipv6 settings
set accept-redirects=no accept-router-advertisements=yes

# ---- Interface List Members ----
/interface list member
add comment=defconf interface=bridge list=LAN
add interface=ether1 list=WAN
add interface=bridge-guest list=GUEST

# ---- IP Adressen ----
/ip address
add address=192.168.42.1/24 interface=bridge network=192.168.42.0
add address=192.168.88.1/24 comment="Gastnetz Gateway" interface=bridge-guest network=192.168.88.0
add address=192.168.89.1/24 comment="WireGuard VPN" interface=wireguard-vpn network=192.168.89.0

# ---- MikroTik Cloud DynDNS + Back-to-Home VPN ----
/ip cloud
set back-to-home-vpn=enabled ddns-enabled=yes ddns-update-interval=1m

# ---- DHCP Client (WAN) ----
/ip dhcp-client
add allow-reconfigure=yes default-route-tables=main interface=ether1

# ---- Statische DHCP Leases (Beispiele) ----
# /ip dhcp-server lease
# add address=192.168.42.105 mac-address=XX:XX:XX:XX:XX:XX server=defconf comment="Geraet 1"
# add address=192.168.42.107 mac-address=XX:XX:XX:XX:XX:XX server=defconf comment="Geraet 2"

# ---- DHCP Server Netzwerke ----
/ip dhcp-server network
add address=192.168.42.0/24 dns-server=192.168.42.1 gateway=192.168.42.1 netmask=24 ntp-server=192.168.42.1
add address=192.168.88.0/24 comment=Gastnetz dns-server=192.168.88.1 gateway=192.168.88.1 netmask=24 ntp-server=192.168.42.1

# ---- DNS-over-HTTPS (Cloudflare) ----
/ip dns
set allow-remote-requests=yes cache-max-ttl=1d cache-size=4096KiB mdns-repeat-ifaces=bridge servers=9.9.9.9,149.112.112.112 use-doh-server=https://1.1.1.1/dns-query verify-doh-cert=yes
/ip dns static
add address=192.168.42.1 comment=defconf name=router.lan type=A
add address=9.9.9.9 comment="DoH Bootstrap Quad9" name=dns.quad9.net type=A
add address=149.112.112.112 comment="DoH Bootstrap Quad9 secondary" name=dns.quad9.net type=A
add address=1.1.1.1 comment="DoH Bootstrap Cloudflare" name=cloudflare-dns.com type=A
add address=1.0.0.1 comment="DoH Bootstrap Cloudflare secondary" name=cloudflare-dns.com type=A
add address=192.168.88.1 comment="Gastnetz Router-Zugang" name=router.guest type=A

# ---- IPv4 Firewall Filter ----
/ip firewall filter
# Input Chain
add action=accept chain=input comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=invalid
add action=accept chain=input comment="defconf: accept ICMP" protocol=icmp
add action=accept chain=input comment="defconf: accept to local loopback (for CAPsMAN)" dst-address=127.0.0.1
add chain=input comment="allow WireGuard" dst-port=443 protocol=udp
add action=accept chain=input comment="Gastnetz: DNS erlauben" dst-port=53 protocol=udp src-address=192.168.88.0/24
add action=accept chain=input comment="Gastnetz: DHCP erlauben" dst-port=67 protocol=udp src-address=192.168.88.0/24
add action=drop chain=input comment="Gastnetz: Router-Zugriff blockieren" src-address=192.168.88.0/24
add action=accept chain=input comment="allow IGMP" protocol=igmp
add action=drop chain=input comment="defconf: drop all not coming from LAN" in-interface-list=!LAN
# Forward Chain
add action=accept chain=forward comment="defconf: accept in ipsec policy" ipsec-policy=in,ipsec
add action=accept chain=forward comment="defconf: accept out ipsec policy" ipsec-policy=out,ipsec
add action=fasttrack-connection chain=forward comment="defconf: fasttrack" connection-state=established,related
add action=accept chain=forward comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" connection-state=invalid
add action=drop chain=forward comment="Gastnetz: LAN-Zugriff blockieren" dst-address=192.168.42.0/24 src-address=192.168.88.0/24
add action=drop chain=forward comment="Gastnetz: VPN-Zugriff blockieren" dst-address=192.168.89.0/24 src-address=192.168.88.0/24
add action=accept chain=forward comment="Gastnetz: Internet erlauben" src-address=192.168.88.0/24
add action=accept chain=forward comment="allow Multicast" dst-address=224.0.0.0/4
add action=drop chain=forward comment="defconf: drop all from WAN not DSTNATed" connection-nat-state=!dstnat connection-state=new in-interface-list=WAN

# ---- IPv4 NAT ----
/ip firewall nat
add action=masquerade chain=srcnat comment="defconf: masquerade" ipsec-policy=out,none out-interface-list=WAN
add action=masquerade chain=srcnat out-interface-list=WAN
add action=masquerade chain=srcnat comment="masq. vpn traffic" src-address=192.168.89.0/24

# ---- Services (gehaertet) ----
/ip service
set ftp disabled=yes
set ssh address=192.168.42.0/24,192.168.89.0/24
set telnet disabled=yes
set www disabled=yes
set winbox address=192.168.42.0/24,192.168.89.0/24
set api disabled=yes
set api-ssl disabled=yes

# ---- UPnP ----
/ip upnp
set enabled=yes
/ip upnp interfaces
add interface=bridge type=internal
add interface=ether1 type=external

# ---- IPv6 Adressen (ULA + NAT) ----
/ipv6 address
add address=fd42::1 comment="LAN IPv6 ULA" interface=bridge
add address=fd42:1::1 comment="Gastnetz IPv6 ULA" interface=bridge-guest
/ipv6 dhcp-client
add add-default-route=yes interface=ether1 request=address

# ---- IPv6 Firewall Address-Lists ----
/ipv6 firewall address-list
add address=::/128 comment="defconf: unspecified address" list=bad_ipv6
add address=::1/128 comment="defconf: lo" list=bad_ipv6
add address=fec0::/10 comment="defconf: site-local" list=bad_ipv6
add address=::ffff:0.0.0.0/96 comment="defconf: ipv4-mapped" list=bad_ipv6
add address=::/96 comment="defconf: ipv4 compat" list=bad_ipv6
add address=100::/64 comment="defconf: discard only" list=bad_ipv6
add address=2001:db8::/32 comment="defconf: documentation" list=bad_ipv6
add address=2001:10::/28 comment="defconf: ORCHID" list=bad_ipv6
add address=3ffe::/16 comment="defconf: 6bone" list=bad_ipv6

# ---- IPv6 Firewall Filter ----
/ipv6 firewall filter
# Input Chain
add action=accept chain=input comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=invalid
add action=accept chain=input comment="defconf: accept ICMPv6" protocol=icmpv6
add action=accept chain=input comment="defconf: accept UDP traceroute" dst-port=33434-33534 protocol=udp
add action=accept chain=input comment="defconf: accept DHCPv6-Client prefix delegation" dst-port=546 protocol=udp src-address=fe80::/10
add chain=input comment="allow WireGuard IPv6" dst-port=443 protocol=udp
add action=drop chain=input comment="defconf: drop everything else not coming from LAN" in-interface-list=!LAN
# Forward Chain
add action=fasttrack-connection chain=forward comment="defconf: fasttrack6" connection-state=established,related
add action=accept chain=forward comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" connection-state=invalid
add action=drop chain=forward comment="defconf: drop packets with bad src ipv6" src-address-list=bad_ipv6
add action=drop chain=forward comment="defconf: drop packets with bad dst ipv6" dst-address-list=bad_ipv6
add action=drop chain=forward comment="defconf: rfc4890 drop hop-limit=1" hop-limit=equal:1 protocol=icmpv6
add action=accept chain=forward comment="defconf: accept ICMPv6" protocol=icmpv6
add action=accept chain=forward comment="defconf: accept HIP" protocol=139
add action=drop chain=forward comment="defconf: drop everything else not coming from LAN" in-interface-list=!LAN

# ---- IPv6 NAT (da DG kein Prefix delegiert) ----
/ipv6 firewall nat
add action=masquerade chain=srcnat comment="IPv6 masquerade" out-interface=ether1

# ---- IPv6 Neighbor Discovery ----
/ipv6 nd
set [ find default=yes ] advertise-dns=yes
add advertise-dns=yes interface=bridge-guest

# ---- IGMP Proxy ----
/routing igmp-proxy
set quick-leave=yes
/routing igmp-proxy interface
add interface=ether1 upstream=yes
add interface=bridge

# ---- System ----
/system clock
set time-zone-name=Europe/Berlin
/system ntp client
set enabled=yes
/system ntp server
set broadcast=yes enabled=yes
/system ntp client servers
add address=de.pool.ntp.org
add address=europe.pool.ntp.org

# ---- MAC Server ----
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
