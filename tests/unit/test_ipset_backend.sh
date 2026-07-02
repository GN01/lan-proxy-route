#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$setup" > /tmp/lpr-ipset-setup.out
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_clients hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_blocked_clients hash:net family inet -exist"
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

if lpr_ipset_render_mangle "br lan" 0x210 all real-ip 198.18.0.0/15 >/tmp/lpr-ipset-bad-iface.out 2>&1; then
	fail "invalid LAN interface accepted"
fi
if lpr_ipset_render_mangle br-lan 0xzz all real-ip 198.18.0.0/15 >/tmp/lpr-ipset-bad-mark.out 2>&1; then
	fail "invalid mark accepted"
fi
if lpr_ipset_render_mangle br-lan 0x210 all real-ip 198.18.0.0/33 >/tmp/lpr-ipset-bad-cidr.out 2>&1; then
	fail "invalid fake CIDR accepted"
fi
if lpr_ipset_render_mangle br-lan 0x210 denylist real-ip 198.18.0.0/15 >/tmp/lpr-ipset-bad-access.out 2>&1; then
	fail "invalid access mode accepted"
fi

routes="$(lpr_ipset_render_policy_route 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$routes" > /tmp/lpr-ipset-routes.out
assert_contains /tmp/lpr-ipset-routes.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-ipset-routes.out "ip route replace default via 192.168.1.2 dev br-lan table 210"

if lpr_ipset_render_policy_route 0x210 210 10210 999.1.1.1 br-lan >/tmp/lpr-ipset-bad-x86.out 2>&1; then
	fail "invalid X86 IP accepted"
fi
if lpr_ipset_render_policy_route 0x210 21a 10210 192.168.1.2 br-lan >/tmp/lpr-ipset-bad-table.out 2>&1; then
	fail "invalid route table accepted"
fi
if lpr_ipset_render_policy_route 0x210 210 10a10 192.168.1.2 br-lan >/tmp/lpr-ipset-bad-priority.out 2>&1; then
	fail "invalid priority accepted"
fi

cleanup="$(lpr_ipset_render_cleanup 0x210 210 10210 br-lan 192.168.1.2)"
printf '%s\n' "$cleanup" > /tmp/lpr-ipset-cleanup.out
assert_contains /tmp/lpr-ipset-cleanup.out "iptables -t mangle -D PREROUTING -i br-lan -j LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "iptables -t mangle -F LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "iptables -t mangle -X LAN_PROXY_ROUTE 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ipset destroy lpr_blocked_clients 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ipset destroy lpr_proxy_v4 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ip route del default via 192.168.1.2 dev br-lan table 210 2>/dev/null || true"
assert_not_contains /tmp/lpr-ipset-cleanup.out "ip route flush table"
