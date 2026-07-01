#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$setup" > /tmp/lpr-ipset-setup.out
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_clients hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_bypass_v4 hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_proxy_v4 hash:net family inet -exist"

out="$(lpr_ipset_render_mangle br-lan 0x210 all real-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-all.out
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -N LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A PREROUTING -i br-lan -j LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_proxy_v4 dst -j MARK --set-mark 0x210"
assert_not_contains /tmp/lpr-ipset-all.out "lpr_clients src"

out="$(lpr_ipset_render_mangle br-lan 0x210 allowlist fake-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-allow.out
assert_contains /tmp/lpr-ipset-allow.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_clients src -m set --match-set lpr_proxy_v4 dst -j MARK --set-mark 0x210"
assert_contains /tmp/lpr-ipset-allow.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_clients src -d 198.18.0.0/15 -j MARK --set-mark 0x210"

out="$(lpr_ipset_render_mangle br-lan 0x210 blocklist mixed 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-block.out
assert_contains /tmp/lpr-ipset-block.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN"

cleanup="$(lpr_ipset_render_cleanup 0x210 210 10210)"
printf '%s\n' "$cleanup" > /tmp/lpr-ipset-cleanup.out
assert_contains /tmp/lpr-ipset-cleanup.out "iptables -t mangle -D PREROUTING -j LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-cleanup.out "ipset destroy lpr_proxy_v4"
assert_contains /tmp/lpr-ipset-cleanup.out "ip route flush table 210"
