#!/bin/sh
set -eu

. ./tests/lib/assert.sh

assert_file_exists Makefile
assert_file_exists root/etc/config/lan_proxy_route
assert_file_exists root/etc/lan-proxy-route/china_ip4.txt
assert_file_exists root/etc/lan-proxy-route/china_ip4.ver

[ ! -f root/etc/lan-proxy-route/gfwlist.txt ] || fail "gfwlist.txt still exists"
[ ! -f root/etc/lan-proxy-route/adblock.txt ] || fail "adblock.txt still exists"
[ ! -f root/usr/share/lan-proxy-route/dnsmasq.sh ] || fail "dnsmasq.sh still exists"

assert_contains Makefile "PKG_NAME:=luci-app-lan-proxy-route"
assert_contains Makefile "LUCI_TITLE:=LuCI support for LAN Proxy Route"
assert_file_exists po/zh_Hans/luci-app-lan-proxy-route.po
assert_contains root/etc/config/lan_proxy_route "config global 'global'"
assert_contains root/etc/config/lan_proxy_route "option backend 'auto'"
assert_contains root/etc/config/lan_proxy_route "config proxy_node 'x86'"
assert_contains root/etc/config/lan_proxy_route "config access 'access'"
assert_contains root/etc/config/lan_proxy_route "option mode 'all'"
assert_contains root/etc/config/lan_proxy_route "config bypass 'bypass'"
assert_not_contains root/etc/config/lan_proxy_route "config dns"
assert_not_contains root/etc/config/lan_proxy_route "dns_mode"
assert_not_contains root/etc/config/lan_proxy_route "fake_ip_cidr"
assert_not_contains root/etc/config/lan_proxy_route "config list"
assert_file_exists root/etc/init.d/lan-proxy-route
assert_file_exists root/usr/share/lan-proxy-route/lan-proxy-route.sh
assert_file_exists root/usr/share/lan-proxy-route/update-chnroute.sh
assert_contains root/etc/init.d/lan-proxy-route "\"\$SERVICE\" diagnose"
assert_contains root/etc/init.d/lan-proxy-route "trace"

# Bundled China list sanity: version stamp and a reasonable entry count.
ver="$(head -n 1 root/etc/lan-proxy-route/china_ip4.ver | tr -cd '0-9')"
[ -n "$ver" ] || fail "china_ip4.ver has no numeric version"
entries="$(grep -c '/' root/etc/lan-proxy-route/china_ip4.txt)"
[ "$entries" -ge 1000 ] || fail "china_ip4.txt has too few entries: $entries"
