#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh

out="$(lpr_nft_render_table br-lan 0x210 all real-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-all.out
assert_contains /tmp/lpr-nft-all.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-nft-all.out "set bypass_v4"
assert_contains /tmp/lpr-nft-all.out "set proxy_v4"
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @bypass_v4 return'
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @proxy_v4 meta mark set 0x210'
assert_not_contains /tmp/lpr-nft-all.out "@clients_v4 ip daddr @proxy_v4"
assert_not_contains /tmp/lpr-nft-all.out "198.18.0.0/15 meta mark"

out="$(lpr_nft_render_table br-lan 0x210 allowlist fake-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-allow.out
assert_contains /tmp/lpr-nft-allow.out "set clients_v4"
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip saddr @clients_v4 ip daddr @proxy_v4 meta mark set 0x210'
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip saddr @clients_v4 ip daddr 198.18.0.0/15 meta mark set 0x210'

out="$(lpr_nft_render_table br-lan 0x210 blocklist mixed 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-block.out
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip saddr @blocked_clients_v4 return'
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip daddr @proxy_v4 meta mark set 0x210'

if lpr_nft_render_table br-lan 0x210 denylist real-ip 198.18.0.0/15 >/tmp/lpr-nft-bad-access.out 2>&1; then
	fail "invalid access mode accepted"
fi
if lpr_nft_render_table "br lan" 0x210 all real-ip 198.18.0.0/15 >/tmp/lpr-nft-bad-iface.out 2>&1; then
	fail "invalid LAN interface accepted"
fi
if lpr_nft_render_table br-lan 0xzz all real-ip 198.18.0.0/15 >/tmp/lpr-nft-bad-mark.out 2>&1; then
	fail "invalid mark accepted"
fi
if lpr_nft_render_table br-lan 0x210 all real-ip 198.18.0.0/33 >/tmp/lpr-nft-bad-cidr.out 2>&1; then
	fail "invalid fake CIDR accepted"
fi

routes="$(lpr_nft_render_policy_route 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$routes" > /tmp/lpr-nft-routes.out
assert_contains /tmp/lpr-nft-routes.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-nft-routes.out "ip route replace default via 192.168.1.2 dev br-lan table 210"

if lpr_nft_render_policy_route 0x210 210 10210 999.1.1.1 br-lan >/tmp/lpr-nft-bad-x86.out 2>&1; then
	fail "invalid X86 IP accepted"
fi
if lpr_nft_render_policy_route 0x210 21a 10210 192.168.1.2 br-lan >/tmp/lpr-nft-bad-table.out 2>&1; then
	fail "invalid route table accepted"
fi
if lpr_nft_render_policy_route 0x210 210 10a10 192.168.1.2 br-lan >/tmp/lpr-nft-bad-priority.out 2>&1; then
	fail "invalid priority accepted"
fi

cleanup="$(lpr_nft_render_cleanup 0x210 210 10210)"
printf '%s\n' "$cleanup" > /tmp/lpr-nft-cleanup.out
assert_contains /tmp/lpr-nft-cleanup.out "nft delete table inet lan_proxy_route 2>/dev/null || true"
assert_contains /tmp/lpr-nft-cleanup.out "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains /tmp/lpr-nft-cleanup.out "ip route flush table 210 2>/dev/null || true"
