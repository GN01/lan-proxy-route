#!/bin/sh
set -eu

. ./tests/lib/assert.sh

svc=./root/usr/share/lan-proxy-route/lan-proxy-route.sh
init=./root/etc/init.d/lan-proxy-route

assert_file_exists "$svc"
assert_file_exists "$init"

sh -n "$svc"
sh -n "$init"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

assert_contains "$init" "EXTRA_COMMANDS=\"diagnose trace\""
assert_not_contains "$init" "dnsmasq"

start_service_block="$(awk '/^start_service\(\)/,/^}/ { print }' "$init")"
diagnose_block="$(awk '/^diagnose\(\)/,/^}/ { print }' "$init")"
status_service_block="$(awk '/^status_service\(\)/,/^}/ { print }' "$init")"

printf '%s\n' "$start_service_block" > "$tmpdir/start_service.block"
printf '%s\n' "$diagnose_block" > "$tmpdir/diagnose.block"
printf '%s\n' "$status_service_block" > "$tmpdir/status_service.block"
assert_contains "$tmpdir/start_service.block" "\"\$SERVICE\" apply"
assert_contains "$tmpdir/diagnose.block" "\"\$SERVICE\" diagnose"
assert_contains "$tmpdir/status_service.block" "\"\$SERVICE\" diagnose"

LPR_DRY_RUN=1 LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" render > /tmp/lpr-service-render.out
assert_contains /tmp/lpr-service-render.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-service-render.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-service-render.out "nft add element inet lan_proxy_route china_v4 {"
assert_not_contains /tmp/lpr-service-render.out "dnsmasq"
assert_not_contains /tmp/lpr-service-render.out "server=/"

LPR_DRY_RUN=1 LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" cleanup > /tmp/lpr-service-clean.out
assert_contains /tmp/lpr-service-clean.out "ipset destroy lpr_china_v4"
assert_contains /tmp/lpr-service-clean.out "iptables -t mangle -D PREROUTING -i br-lan -j LAN_PROXY_ROUTE 2>/dev/null || true"
assert_not_contains /tmp/lpr-service-clean.out "--dport 53"
assert_not_contains /tmp/lpr-service-clean.out "--dport 853"

LPR_DRY_RUN=1 LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" cleanup > /tmp/lpr-service-clean-nft.out
assert_contains /tmp/lpr-service-clean-nft.out "nft list table inet lan_proxy_route >/dev/null 2>&1 && nft delete table inet lan_proxy_route || true"
assert_not_contains /tmp/lpr-service-clean-nft.out "dns_hijack"
assert_not_contains /tmp/lpr-service-clean-nft.out "dns_dot_block"

if LPR_BACKEND=nftset LPR_X86_IP=999.1.1.1 sh "$svc" validate >/tmp/lpr-invalid.out 2>&1; then
	fail "invalid X86 IP passed validation"
fi
assert_contains /tmp/lpr-invalid.out "invalid proxy IP"

if LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_CHINA_FILE="$tmpdir/no-such-file" \
	sh "$svc" validate >/tmp/lpr-missing-china.out 2>&1; then
	fail "missing china list passed validation"
fi
assert_contains /tmp/lpr-missing-china.out "china IP list missing"

cat > "$tmpdir/lpr-exec" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LPR_EXEC_LOG"
EOF
chmod +x "$tmpdir/lpr-exec"

exec_log="$tmpdir/exec.log"
LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" \
LPR_EXEC_LOG="$exec_log" sh "$svc" cleanup
assert_contains "$exec_log" "ipset destroy lpr_china_v4 2>/dev/null || true"

: > "$exec_log"
LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" \
LPR_EXEC_LOG="$exec_log" sh "$svc" cleanup
assert_contains "$exec_log" "nft list table inet lan_proxy_route >/dev/null 2>&1 && nft delete table inet lan_proxy_route || true"

: > "$exec_log"
LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" \
LPR_EXEC_LOG="$exec_log" LPR_STATE_FILE="$tmpdir/apply-state-1" sh "$svc" apply
assert_contains "$exec_log" "ipset create lpr_china_v4 hash:net family inet maxelem 65536 -exist"
assert_contains "$exec_log" "ipset restore"
assert_contains "$exec_log" "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_china_v4 dst -j RETURN"

cat > "$tmpdir/old-state" <<'EOF'
backend=ipset
mark=0x333
table=333
priority=10333
x86_ip=192.168.33.2
lan_if=br-old
EOF

: > "$exec_log"
LPR_BACKEND=nftset LPR_MARK=0x444 LPR_TABLE=444 LPR_PRIORITY=10444 LPR_X86_IP=192.168.44.2 LPR_LAN_IF=br-new \
LPR_STATE_FILE="$tmpdir/old-state" LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" LPR_EXEC_LOG="$exec_log" \
sh "$svc" cleanup
assert_contains "$exec_log" "ip route del default via 192.168.44.2 dev br-new table 444 2>/dev/null || true"
assert_contains "$exec_log" "ip rule del fwmark 0x444 lookup 444 priority 10444 2>/dev/null || true"
assert_contains "$exec_log" "ip route del default via 192.168.33.2 dev br-old table 333 2>/dev/null || true"
assert_contains "$exec_log" "ip rule del fwmark 0x333 lookup 333 priority 10333 2>/dev/null || true"
[ ! -f "$tmpdir/old-state" ] || fail "runtime state file still exists: $tmpdir/old-state"

state_file="$tmpdir/runtime-state"
: > "$exec_log"
LPR_BACKEND=ipset LPR_MARK=0x555 LPR_TABLE=555 LPR_PRIORITY=10555 LPR_X86_IP=192.168.55.2 LPR_LAN_IF=br-state \
LPR_STATE_FILE="$state_file" LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" LPR_EXEC_LOG="$exec_log" \
sh "$svc" apply
assert_file_exists "$state_file"
assert_contains "$state_file" "backend=ipset"
assert_contains "$state_file" "mark=0x555"
assert_contains "$state_file" "table=555"
assert_contains "$state_file" "priority=10555"
assert_contains "$state_file" "x86_ip=192.168.55.2"
assert_contains "$state_file" "lan_if=br-state"
