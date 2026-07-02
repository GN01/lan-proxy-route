#!/bin/sh
set -eu

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

nft_cleanup="$(lpr_nft_render_cleanup 0x210 210 10210)"
printf '%s\n' "$nft_cleanup" > "$tmpdir/lpr-final-nft-cleanup.out"
assert_contains "$tmpdir/lpr-final-nft-cleanup.out" "nft list table inet lan_proxy_route >/dev/null 2>&1 && nft delete table inet lan_proxy_route || true"
assert_contains "$tmpdir/lpr-final-nft-cleanup.out" "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-nft-cleanup.out" "ip route flush table 210 2>/dev/null || true"

ipset_setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$ipset_setup" > "$tmpdir/lpr-final-ipset-setup.out"
assert_contains "$tmpdir/lpr-final-ipset-setup.out" "ipset create lpr_clients hash:net family inet -exist"
assert_contains "$tmpdir/lpr-final-ipset-setup.out" "ipset create lpr_blocked_clients hash:net family inet -exist"
assert_contains "$tmpdir/lpr-final-ipset-setup.out" "ipset create lpr_bypass_v4 hash:net family inet -exist"
assert_contains "$tmpdir/lpr-final-ipset-setup.out" "ipset create lpr_proxy_v4 hash:net family inet -exist"

ipset_cleanup="$(lpr_ipset_render_cleanup 0x210 210 10210 br-lan)"
printf '%s\n' "$ipset_cleanup" > "$tmpdir/lpr-final-ipset-cleanup.out"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "iptables -t mangle -D PREROUTING -i br-lan -j LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "iptables -t mangle -F LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "iptables -t mangle -X LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ipset destroy lpr_clients 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ipset destroy lpr_blocked_clients 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ipset destroy lpr_bypass_v4 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ipset destroy lpr_proxy_v4 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains "$tmpdir/lpr-final-ipset-cleanup.out" "ip route flush table 210 2>/dev/null || true"
