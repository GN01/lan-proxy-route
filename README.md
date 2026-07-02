# LAN Proxy Route

`luci-app-lan-proxy-route` is a lightweight OpenWrt LuCI service that routes selected LAN clients' foreign traffic to one LAN-side X86 transparent proxy host.

OpenWrt handles DNS entry control, set filling, packet marks, policy routing, and diagnostics. The X86 host handles transparent proxy interception and outbound proxy policy.

The primary backend is `nftset` for OpenWrt 25.12. The compatibility backend is `ipset` for QSDK12.5/QWRT.

Runtime dependencies are declared for the primary `firewall4`/`nftables` path and the advertised `ipset`/`iptables` compatibility path. Some QSDK feeds rename or split iptables/ipset packages; if a target feed does not provide `iptables-mod-ipset`, install the equivalent package that supplies `-m set` support.

## Local Checks

Run:

```sh
sh tests/run.sh
```

## Runtime Verification

On OpenWrt 25.12 with nftset:

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
nft list table inet lan_proxy_route
ip rule show
ip route show table 210
```

On QSDK12.5/QWRT with ipset:

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
ipset list lpr_proxy_v4
iptables -t mangle -S LAN_PROXY_ROUTE
ip rule show
ip route show table 210
```

DNS checks:

```sh
nslookup google.com 192.168.1.1
nslookup doubleclick.net 192.168.1.1
```

Traffic checks:

```sh
ip route get 8.8.8.8 mark 0x210
```
