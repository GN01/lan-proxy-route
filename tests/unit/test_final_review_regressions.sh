#!/bin/sh
set -eu

. ./tests/lib/assert.sh

svc=./root/usr/share/lan-proxy-route/lan-proxy-route.sh
rpc=./root/usr/libexec/rpcd/lan-proxy-route

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

cat > "$tmpdir/china_ip4.txt" <<'EOF'
1.0.1.0/24
1.0.2.0/23
1.0.8.0/21
EOF
printf '20260704060757\n' > "$tmpdir/china_ip4.ver"

cat > "$tmpdir/lan_proxy_route" <<EOF
config global
	option enabled '1'
	option backend 'nftset'
	option mark '0x321'
	option table '321'
	option priority '10321'
	option lan_if 'br-test'

config proxy_node 'x86'
	option ip '192.168.50.2'

config access
	option mode 'allowlist'
	list allow_ip '192.168.50.10'
	list allow_cidr '192.168.50.0/24'
	list block_ip '192.168.50.20'
	list block_cidr '192.168.60.0/24'

config bypass
	list cidr '203.0.113.0/24'
EOF

LPR_DRY_RUN=1 LPR_CONFIG="$tmpdir/lan_proxy_route" LPR_CHINA_FILE="$tmpdir/china_ip4.txt" \
	LPR_CHINA_VER_FILE="$tmpdir/china_ip4.ver" sh "$svc" render > "$tmpdir/render.out"
assert_contains "$tmpdir/render.out" "ip rule add fwmark 0x321 lookup 321 priority 10321"
assert_contains "$tmpdir/render.out" "ip route replace 192.168.50.2/32 dev br-test table 321"
assert_contains "$tmpdir/render.out" "ip route replace default via 192.168.50.2 dev br-test table 321 onlink"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route clients_v4 { 192.168.50.0/24 }"
assert_not_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route clients_v4 { 192.168.50.10 }"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route blocked_clients_v4 { 192.168.50.20 }"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route blocked_clients_v4 { 192.168.60.0/24 }"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route bypass_v4 { 203.0.113.0/24 }"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route bypass_v4 { 192.168.50.2 }"
assert_contains "$tmpdir/render.out" "nft add element inet lan_proxy_route china_v4 { 1.0.1.0/24, 1.0.2.0/23, 1.0.8.0/21 }"
assert_eq 1 "$(grep -Fc "nft add element inet lan_proxy_route bypass_v4 { 192.168.50.2 }" "$tmpdir/render.out")"
assert_not_contains "$tmpdir/render.out" "table inet lan_proxy_route {"
assert_not_contains "$tmpdir/render.out" "dnsmasq"
assert_not_contains "$tmpdir/render.out" "server=/"
assert_not_contains "$tmpdir/render.out" "proxy_v4"

cat > "$tmpdir/default-overlap" <<EOF
config global 'global'
	option enabled '1'
	option backend 'nftset'

config proxy_node 'x86'
	option ip '192.168.1.2'

config bypass 'bypass'
	list cidr '192.168.0.0/16'
	list cidr '192.168.1.0/24'
EOF

LPR_DRY_RUN=1 LPR_CONFIG="$tmpdir/default-overlap" LPR_CHINA_FILE="$tmpdir/china_ip4.txt" \
	LPR_CHINA_VER_FILE="$tmpdir/china_ip4.ver" sh "$svc" render > "$tmpdir/default-overlap.out"
assert_contains "$tmpdir/default-overlap.out" "nft add element inet lan_proxy_route bypass_v4 { 192.168.0.0/16 }"
assert_not_contains "$tmpdir/default-overlap.out" "nft add element inet lan_proxy_route bypass_v4 { 192.168.1.0/24 }"
assert_not_contains "$tmpdir/default-overlap.out" "nft add element inet lan_proxy_route bypass_v4 { 192.168.1.2 }"

cat > "$tmpdir/disabled" <<EOF
config global
	option enabled '0'
	option backend 'ipset'
	option mark '0x444'
	option table '444'
	option priority '10444'
	option lan_if 'br-off'

config proxy_node 'x86'
	option ip '192.168.44.2'
EOF

LPR_DRY_RUN=1 LPR_CONFIG="$tmpdir/disabled" sh "$svc" render > "$tmpdir/disabled-render.out"
assert_not_contains "$tmpdir/disabled-render.out" "ip rule add"
assert_not_contains "$tmpdir/disabled-render.out" "iptables -t mangle"
assert_not_contains "$tmpdir/disabled-render.out" "nft add"

cat > "$tmpdir/runner" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$LPR_EXEC_LOG"
EOF
chmod +x "$tmpdir/runner"
exec_log="$tmpdir/exec.log"
LPR_CONFIG="$tmpdir/lan_proxy_route" LPR_COMMAND_RUNNER="$tmpdir/runner" LPR_EXEC_LOG="$exec_log" \
	LPR_CHINA_FILE="$tmpdir/china_ip4.txt" LPR_CHINA_VER_FILE="$tmpdir/china_ip4.ver" \
	LPR_STATE_FILE="$tmpdir/apply-state" sh "$svc" apply
assert_contains "$exec_log" "nft add table inet lan_proxy_route"
assert_contains "$exec_log" "nft add element inet lan_proxy_route china_v4 { 1.0.1.0/24, 1.0.2.0/23, 1.0.8.0/21 }"
assert_not_contains "$exec_log" "table inet lan_proxy_route {"
assert_not_contains "$exec_log" "set clients_v4 {"

. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

lpr_nft_render_cleanup 0x321 321 10321 192.168.50.2 br-test > "$tmpdir/nft-cleanup.out"
assert_contains "$tmpdir/nft-cleanup.out" "ip route del default via 192.168.50.2 dev br-test table 321 2>/dev/null || true"
assert_contains "$tmpdir/nft-cleanup.out" "ip route del 192.168.50.2/32 dev br-test table 321 2>/dev/null || true"
assert_not_contains "$tmpdir/nft-cleanup.out" "ip route flush table"

lpr_ipset_render_cleanup 0x321 321 10321 br-test 192.168.50.2 > "$tmpdir/ipset-cleanup.out"
assert_contains "$tmpdir/ipset-cleanup.out" "ip route del default via 192.168.50.2 dev br-test table 321 2>/dev/null || true"
assert_contains "$tmpdir/ipset-cleanup.out" "ip route del 192.168.50.2/32 dev br-test table 321 2>/dev/null || true"
assert_not_contains "$tmpdir/ipset-cleanup.out" "ip route flush table"

LPR_CONFIG="$tmpdir/lan_proxy_route" LPR_CHINA_FILE="$tmpdir/china_ip4.txt" \
	LPR_CHINA_VER_FILE="$tmpdir/china_ip4.ver" sh "$svc" diagnose > "$tmpdir/diag.json"
assert_contains "$tmpdir/diag.json" '"policy_rule_present"'
assert_contains "$tmpdir/diag.json" '"policy_route_present"'
assert_contains "$tmpdir/diag.json" '"china_set_present"'
assert_contains "$tmpdir/diag.json" '"china_list_version":"20260704060757"'
assert_contains "$tmpdir/diag.json" '"china_list_entries":3'
assert_contains "$tmpdir/diag.json" '"x86_reachable"'
assert_not_contains "$tmpdir/diag.json" '"dns_hijack_present"'
assert_not_contains "$tmpdir/diag.json" '"dot_block_present"'
assert_not_contains "$tmpdir/diag.json" '"dnsmasq_config_present"'

cat > "$tmpdir/ip" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LPR_IP_LOG"
case "$*" in
	route\ get\ 8.8.8.8\ mark\ 0x321*)
		printf '8.8.8.8 via 192.168.50.2 dev br-test mark 0x321\n'
		exit 0
		;;
	route\ get\ 1.1.1.1\ mark\ 0x321*)
		printf '1.1.1.1 via 192.168.50.2 dev br-test mark 0x321\n'
		exit 0
		;;
esac
exit 1
EOF
chmod +x "$tmpdir/ip"
LPR_RPCD_SERVICE="$svc" LPR_CONFIG="$tmpdir/lan_proxy_route" LPR_CHINA_FILE="$tmpdir/china_ip4.txt" \
	PATH="$tmpdir:$PATH" LPR_IP_LOG="$tmpdir/ip.log" \
	sh "$rpc" call test_route '{"dst":"8.8.8.8"}' > "$tmpdir/rpc-route.json"
assert_contains "$tmpdir/rpc-route.json" '"ok":true'
assert_contains "$tmpdir/rpc-route.json" '"matched":true'
assert_contains "$tmpdir/ip.log" "route get 8.8.8.8 mark 0x321"
assert_not_contains "$tmpdir/rpc-route.json" "test-route is rendered by diagnostics"

: > "$tmpdir/ip.log"
printf '{"dst":"1.1.1.1"}' > "$tmpdir/rpc-route.stdin"
LPR_RPCD_SERVICE="$svc" LPR_CONFIG="$tmpdir/lan_proxy_route" LPR_CHINA_FILE="$tmpdir/china_ip4.txt" \
	PATH="$tmpdir:$PATH" LPR_IP_LOG="$tmpdir/ip.log" \
	sh "$rpc" call test_route < "$tmpdir/rpc-route.stdin" > "$tmpdir/rpc-route-stdin.json"
assert_contains "$tmpdir/rpc-route-stdin.json" '"ok":true'
assert_contains "$tmpdir/rpc-route-stdin.json" '"matched":true'
assert_contains "$tmpdir/ip.log" "route get 1.1.1.1 mark 0x321"

cat > "$tmpdir/rpc-service" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LPR_RPC_SERVICE_LOG"
exit 0
EOF
chmod +x "$tmpdir/rpc-service"
cat > "$tmpdir/init.d-firewall" <<'EOF'
#!/bin/sh
printf 'firewall %s\n' "$*" >> "$LPR_RPC_INIT_LOG"
exit 0
EOF
chmod +x "$tmpdir/init.d-firewall"

LPR_RPCD_SERVICE="$tmpdir/rpc-service" LPR_RPC_SERVICE_LOG="$tmpdir/rpc-service.log" \
	LPR_INIT_FIREWALL="$tmpdir/init.d-firewall" \
	LPR_RPC_INIT_LOG="$tmpdir/rpc-init.log" sh "$rpc" call reload > "$tmpdir/rpc-reload.json"
assert_contains "$tmpdir/rpc-reload.json" '"ok":true'
assert_contains "$tmpdir/rpc-service.log" "cleanup"
assert_contains "$tmpdir/rpc-service.log" "apply"
assert_contains "$tmpdir/rpc-init.log" "firewall reload"

assert_contains Makefile "+firewall4"
assert_contains Makefile "+nftables"
assert_contains Makefile "PKG_VERSION:=0.2.0"
assert_not_contains Makefile "+ipset"
assert_not_contains Makefile "+iptables"
assert_not_contains Makefile "+dnsmasq-full"
