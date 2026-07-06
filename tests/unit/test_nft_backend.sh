#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

out="$(lpr_nft_render_table br-lan 0x210 all)"
printf '%s\n' "$out" > /tmp/lpr-nft-all.out
assert_contains /tmp/lpr-nft-all.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-nft-all.out "nft add set inet lan_proxy_route bypass_v4"
assert_contains /tmp/lpr-nft-all.out "nft add set inet lan_proxy_route china_v4"
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @bypass_v4 return'
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @china_v4 return'
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" meta mark set 0x210'
assert_not_contains /tmp/lpr-nft-all.out "proxy_v4"
assert_not_contains /tmp/lpr-nft-all.out "dns_hijack"

out="$(lpr_nft_render_table br-lan 0x210 allowlist)"
printf '%s\n' "$out" > /tmp/lpr-nft-allow.out
assert_contains /tmp/lpr-nft-allow.out "nft add set inet lan_proxy_route clients_v4"
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip saddr @clients_v4 meta mark set 0x210'
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip daddr @china_v4 return'

out="$(lpr_nft_render_table br-lan 0x210 blocklist)"
printf '%s\n' "$out" > /tmp/lpr-nft-block.out
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip saddr @blocked_clients_v4 return'
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip daddr @bypass_v4 return'
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip daddr @china_v4 return'
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" meta mark set 0x210'
blocked_line="$(grep -n 'blocked_clients_v4 return' /tmp/lpr-nft-block.out | head -n1 | cut -d: -f1)"
bypass_line="$(grep -n 'bypass_v4 return' /tmp/lpr-nft-block.out | head -n1 | cut -d: -f1)"
china_line="$(grep -n 'china_v4 return' /tmp/lpr-nft-block.out | head -n1 | cut -d: -f1)"
mark_line="$(grep -n 'meta mark set 0x210' /tmp/lpr-nft-block.out | head -n1 | cut -d: -f1)"
[ "$blocked_line" -lt "$bypass_line" ] || fail "blocklist rule must precede bypass"
[ "$bypass_line" -lt "$china_line" ] || fail "bypass rule must precede china direct"
[ "$china_line" -lt "$mark_line" ] || fail "china direct rule must precede proxy mark"

if lpr_nft_render_table br-lan 0x210 denylist >/tmp/lpr-nft-bad-access.out 2>&1; then
	fail "invalid access mode accepted"
fi
if lpr_nft_render_table "br lan" 0x210 all >/tmp/lpr-nft-bad-iface.out 2>&1; then
	fail "invalid LAN interface accepted"
fi
if lpr_nft_render_table br-lan 0xzz all >/tmp/lpr-nft-bad-mark.out 2>&1; then
	fail "invalid mark accepted"
fi

# Chunked bulk loading of a CIDR list file.
{
	i=1
	while [ "$i" -le 1200 ]; do
		printf '10.%s.%s.0/24\n' "$((i / 256))" "$((i % 256))"
		i=$((i + 1))
	done
	printf '# comment line\n'
	printf '\n'
	printf 'not-a-cidr\n'
} > "$tmpdir/china.txt"

lpr_nft_render_file_elements china_v4 "$tmpdir/china.txt" 500 > "$tmpdir/china-chunks.out"
chunk_lines="$(grep -c '^nft add element inet lan_proxy_route china_v4 {' "$tmpdir/china-chunks.out")"
assert_eq 3 "$chunk_lines"
assert_contains "$tmpdir/china-chunks.out" "10.0.1.0/24, 10.0.2.0/24"
assert_not_contains "$tmpdir/china-chunks.out" "not-a-cidr"
assert_not_contains "$tmpdir/china-chunks.out" "# comment"

first_chunk="$(head -n 1 "$tmpdir/china-chunks.out")"
first_count="$(printf '%s\n' "$first_chunk" | tr ',' '\n' | wc -l | tr -d ' ')"
assert_eq 500 "$first_count"

if lpr_nft_render_file_elements proxy_v4 "$tmpdir/china.txt" 500 >/dev/null 2>&1; then
	fail "invalid set name accepted for file elements"
fi
if lpr_nft_render_file_elements china_v4 "$tmpdir/missing.txt" 500 >/dev/null 2>&1; then
	fail "missing file accepted for file elements"
fi

routes="$(lpr_nft_render_policy_route 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$routes" > /tmp/lpr-nft-routes.out
assert_contains /tmp/lpr-nft-routes.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-nft-routes.out "ip route replace 192.168.1.2/32 dev br-lan table 210"
assert_contains /tmp/lpr-nft-routes.out "ip route replace default via 192.168.1.2 dev br-lan table 210 onlink"

if lpr_nft_render_policy_route 0x210 210 10210 999.1.1.1 br-lan >/tmp/lpr-nft-bad-x86.out 2>&1; then
	fail "invalid X86 IP accepted"
fi
if lpr_nft_render_policy_route 0x210 21a 10210 192.168.1.2 br-lan >/tmp/lpr-nft-bad-table.out 2>&1; then
	fail "invalid route table accepted"
fi
if lpr_nft_render_policy_route 0x210 210 10a10 192.168.1.2 br-lan >/tmp/lpr-nft-bad-priority.out 2>&1; then
	fail "invalid priority accepted"
fi

cleanup="$(lpr_nft_render_cleanup 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$cleanup" > /tmp/lpr-nft-cleanup.out
assert_contains /tmp/lpr-nft-cleanup.out "nft list table inet lan_proxy_route >/dev/null 2>&1 && nft delete table inet lan_proxy_route || true"
assert_contains /tmp/lpr-nft-cleanup.out "ip rule del fwmark 0x210 lookup 210 priority 10210 2>/dev/null || true"
assert_contains /tmp/lpr-nft-cleanup.out "ip route del default via 192.168.1.2 dev br-lan table 210 2>/dev/null || true"
assert_contains /tmp/lpr-nft-cleanup.out "ip route del 192.168.1.2/32 dev br-lan table 210 2>/dev/null || true"
assert_not_contains /tmp/lpr-nft-cleanup.out "ip route flush table"
