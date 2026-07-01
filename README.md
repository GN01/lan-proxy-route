# LAN Proxy Route

`luci-app-lan-proxy-route` is a lightweight OpenWrt LuCI service that routes selected LAN clients' foreign traffic to one LAN-side X86 transparent proxy host.

OpenWrt handles DNS entry control, set filling, packet marks, policy routing, and diagnostics. The X86 host handles transparent proxy interception and outbound proxy policy.

The primary backend is `nftset` for OpenWrt 25.12. The compatibility backend is `ipset` for QSDK12.5/QWRT.

## Local Checks

Run:

```sh
sh tests/run.sh
```
