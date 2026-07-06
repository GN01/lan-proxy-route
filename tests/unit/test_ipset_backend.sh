#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$setup" > /tmp/lpr-ipset-setup.out
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_clients hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_blocked_clients hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_bypass_v4 hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_china_v4 hash:net family inet maxelem 65536 -exist"
assert_not_contains /tmp/lpr-ipset-setup.out "lpr_proxy_v4"

out="$(lpr_ipset_render_mangle br-lan 0x210 all)"
printf '%s\n' "$out" > /tmp/lpr-ipset-all.out
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -N LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A PREROUTING -i br-lan -j LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_china_v4 dst -j RETURN"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -j MARK --set-mark 0x210"
assert_not_contains /tmp/lpr-ipset-all.out "lpr_clients src"

out="$(lpr_ipset_render_mangle br-lan 0x210 allowlist)"
printf '%s\n' "$out" > /tmp/lpr-ipset-allow.out
assert_contains /tmp/lpr-ipset-allow.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_clients src -j MARK --set-mark 0x210"

out="$(lpr_ipset_render_mangle br-lan 0x210 blocklist)"
printf '%s\n' "$out" > /tmp/lpr-ipset-block.out
assert_contains /tmp/lpr-ipset-block.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN"
assert_contains /tmp/lpr-ipset-block.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN"
assert_contains /tmp/lpr-ipset-block.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_china_v4 dst -j RETURN"
blocked_line="$(grep -n 'lpr_blocked_clients src -j RETURN' /tmp/lpr-ipset-block.out | head -n1 | cut -d: -f1)"
bypass_line="$(grep -n 'lpr_bypass_v4 dst -j RETURN' /tmp/lpr-ipset-block.out | head -n1 | cut -d: -f1)"
china_line="$(grep -n 'lpr_china_v4 dst -j RETURN' /tmp/lpr-ipset-block.out | head -n1 | cut -d: -f1)"
mark_line="$(grep -n 'MARK --set-mark 0x210' /tmp/lpr-ipset-block.out | head -n1 | cut -d: -f1)"
[ "$blocked_line" -lt "$bypass_line" ] || fail "blocklist rule must precede bypass"
[ "$bypass_line" -lt "$china_line" ] || fail "bypass rule must precede china direct"
[ "$china_line" -lt "$mark_line" ] || fail "china direct rule must precede proxy mark"

if lpr_ipset_render_mangle "br lan" 0x210 all >/tmp/lpr-ipset-bad-iface.out 2>&1; then
	fail "invalid LAN interface accepted"
fi
if lpr_ipset_render_mangle br-lan 0xzz all >/tmp/lpr-ipset-bad-mark.out 2>&1; then
	fail "invalid mark accepted"
fi
if lpr_ipset_render_mangle br-lan 0x210 denylist >/tmp/lpr-ipset-bad-access.out 2>&1; then
	fail "invalid access mode accepted"
fi

# Chunked bulk loading of a CIDR list file via ipset restore.
{
	i=1
	while [ "$i" -le 1200 ]; do
		printf '10.%s.%s.0/24\n' "$((i / 256))" "$((i % 256))"
		i=$((i + 1))
	done
	printf '# comment line\n'
	printf 'not-a-cidr\n'
} > "$tmpdir/china.txt"

lpr_ipset_render_file_elements lpr_china_v4 "$tmpdir/china.txt" 500 > "$tmpdir/china-chunks.out"
chunk_lines="$(grep -c 'ipset restore' "$tmpdir/china-chunks.out")"
assert_eq 3 "$chunk_lines"
assert_contains "$tmpdir/china-chunks.out" "add lpr_china_v4 10.0.1.0/24 -exist"
assert_not_contains "$tmpdir/china-chunks.out" "not-a-cidr"

if lpr_ipset_render_file_elements lpr_proxy_v4 "$tmpdir/china.txt" 500 >/dev/null 2>&1; then
	fail "invalid set name accepted for file elements"
fi
if lpr_ipset_render_file_elements lpr_china_v4 "$tmpdir/missing.txt" 500 >/dev/null 2>&1; then
	fail "missing file accepted for file elements"
fi

# Each rendered chunk command must be executable and feed valid restore input.
first_chunk_cmd="$(head -n 1 "$tmpdir/china-chunks.out")"
printf_part="${first_chunk_cmd% | ipset restore}"
sh -c "$printf_part" > "$tmpdir/restore-input.out"
restore_count="$(grep -c '^add lpr_china_v4 ' "$tmpdir/restore-input.out")"
assert_eq 500 "$restore_count"

routes="$(lpr_ipset_render_policy_route 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$routes" > /tmp/lpr-ipset-routes.out
assert_contains /tmp/lpr-ipset-routes.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-ipset-routes.out "ip route replace 192.168.1.2/32 dev br-lan table 210"
assert_contains /tmp/lpr-ipset-routes.out "ip route replace default via 192.168.1.2 dev br-lan table 210 onlink"

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
assert_contains /tmp/lpr-ipset-cleanup.out "ipset destroy lpr_china_v4 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ip route del default via 192.168.1.2 dev br-lan table 210 2>/dev/null || true"
assert_contains /tmp/lpr-ipset-cleanup.out "ip route del 192.168.1.2/32 dev br-lan table 210 2>/dev/null || true"
assert_not_contains /tmp/lpr-ipset-cleanup.out "ip route flush table"
