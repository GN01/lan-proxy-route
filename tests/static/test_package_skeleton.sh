#!/bin/sh
set -eu

. ./tests/lib/assert.sh

assert_file_exists Makefile
assert_file_exists root/etc/config/lan_proxy_route
assert_file_exists root/etc/lan-proxy-route/gfwlist.txt
assert_file_exists root/etc/lan-proxy-route/adblock.txt
assert_file_exists root/etc/lan-proxy-route/custom-proxy-domains.txt
assert_file_exists root/etc/lan-proxy-route/custom-bypass-domains.txt

assert_contains Makefile "PKG_NAME:=luci-app-lan-proxy-route"
assert_contains Makefile "LUCI_TITLE:=LuCI support for LAN Proxy Route"
assert_contains root/etc/config/lan_proxy_route "config global"
assert_contains root/etc/config/lan_proxy_route "option backend 'auto'"
assert_contains root/etc/config/lan_proxy_route "option dns_mode 'real-ip'"
assert_contains root/etc/config/lan_proxy_route "config proxy_node 'x86'"
assert_contains root/etc/config/lan_proxy_route "config access"
assert_contains root/etc/config/lan_proxy_route "option mode 'all'"
assert_contains root/etc/config/lan_proxy_route "config bypass"
assert_file_exists root/etc/init.d/lan-proxy-route
assert_file_exists root/usr/share/lan-proxy-route/lan-proxy-route.sh
assert_contains root/etc/init.d/lan-proxy-route "\"\$SERVICE\" diagnose"
