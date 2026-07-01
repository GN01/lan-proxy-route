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

LPR_DRY_RUN=1 LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" render > /tmp/lpr-service-render.out
assert_contains /tmp/lpr-service-render.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-service-render.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-service-render.out "server=/google.com/192.168.1.2#53"

LPR_DRY_RUN=1 LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" cleanup > /tmp/lpr-service-clean.out
assert_contains /tmp/lpr-service-clean.out "ipset destroy lpr_proxy_v4"
assert_contains /tmp/lpr-service-clean.out "iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true"
assert_contains /tmp/lpr-service-clean.out "iptables -D FORWARD -i br-lan -p tcp --dport 853 -j REJECT 2>/dev/null || true"
assert_contains /tmp/lpr-service-clean.out "iptables -t mangle -D PREROUTING -i br-lan -j LAN_PROXY_ROUTE 2>/dev/null || true"

if LPR_BACKEND=nftset LPR_X86_IP=999.1.1.1 sh "$svc" validate >/tmp/lpr-invalid.out 2>&1; then
	fail "invalid X86 IP passed validation"
fi
assert_contains /tmp/lpr-invalid.out "invalid proxy IP"

cat > "$tmpdir/lpr-exec" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LPR_EXEC_LOG"
EOF
chmod +x "$tmpdir/lpr-exec"

exec_log="$tmpdir/exec.log"
dnsmasq_conf="$tmpdir/lan-proxy-route.conf"
LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" \
LPR_EXEC_LOG="$exec_log" LPR_DNSMASQ_CONF="$dnsmasq_conf" sh "$svc" cleanup
assert_contains "$exec_log" "ipset destroy lpr_proxy_v4 2>/dev/null || true"
assert_contains "$exec_log" "iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true"

: > "$exec_log"
LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan LPR_COMMAND_RUNNER="$tmpdir/lpr-exec" \
LPR_EXEC_LOG="$exec_log" LPR_DNSMASQ_CONF="$dnsmasq_conf" sh "$svc" apply
assert_file_exists "$dnsmasq_conf"
assert_contains "$dnsmasq_conf" "server=/google.com/192.168.1.2#53"
assert_not_contains "$exec_log" "server=/google.com/192.168.1.2#53"
assert_contains "$exec_log" "iptables -t nat -A PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53"
