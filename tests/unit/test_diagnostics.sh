#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/diagnostics.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
# min-bin simulates a system without nft/ipset while keeping coreutils.
mkdir -p "$tmpdir/min-bin"
for tool in cat head tr grep sed awk; do
	ln -s "$(command -v "$tool")" "$tmpdir/min-bin/$tool"
done

cat > "$tmpdir/china_ip4.txt" <<'EOF'
# comment
1.0.1.0/24
1.0.2.0/23

1.0.8.0/21
EOF
printf '20260704060757\n' > "$tmpdir/china_ip4.ver"

LPR_CHINA_FILE="$tmpdir/china_ip4.txt"
LPR_CHINA_VER_FILE="$tmpdir/china_ip4.ver"

json="$(lpr_diag_json nftset 192.168.1.2 br-lan 0x210 210 10210 "" 1)"
printf '%s\n' "$json" > "$tmpdir/lpr-diag.json"
assert_contains "$tmpdir/lpr-diag.json" '"backend":"nftset"'
assert_contains "$tmpdir/lpr-diag.json" '"enabled":true'
assert_contains "$tmpdir/lpr-diag.json" '"running":false'
assert_contains "$tmpdir/lpr-diag.json" '"x86_ip":"192.168.1.2"'
assert_contains "$tmpdir/lpr-diag.json" '"lan_if":"br-lan"'
assert_contains "$tmpdir/lpr-diag.json" '"mark":"0x210"'
assert_contains "$tmpdir/lpr-diag.json" '"table":"210"'
assert_contains "$tmpdir/lpr-diag.json" '"priority":"10210"'
assert_contains "$tmpdir/lpr-diag.json" '"china_set_present"'
assert_contains "$tmpdir/lpr-diag.json" '"china_list_version":"20260704060757"'
assert_contains "$tmpdir/lpr-diag.json" '"china_list_entries":3'
assert_not_contains "$tmpdir/lpr-diag.json" '"dnsmasq'
assert_not_contains "$tmpdir/lpr-diag.json" '"dns_hijack_present"'
assert_not_contains "$tmpdir/lpr-diag.json" '"dot_block_present"'

json="$(lpr_diag_json unknown 192.168.1.2 br-lan 0x210 210 10210 "no backend" 0)"
printf '%s\n' "$json" > "$tmpdir/lpr-diag-unknown.json"
assert_contains "$tmpdir/lpr-diag-unknown.json" '"enabled":false'
assert_contains "$tmpdir/lpr-diag-unknown.json" '"running":false'
assert_contains "$tmpdir/lpr-diag-unknown.json" '"china_set_present":false'
assert_contains "$tmpdir/lpr-diag-unknown.json" '"backend_error":"no backend"'

rpc=./root/usr/libexec/rpcd/lan-proxy-route
assert_file_exists "$rpc"
sh -n "$rpc"

LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan \
	sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > "$tmpdir/lpr-cli-diag.json"
assert_contains "$tmpdir/lpr-cli-diag.json" '"backend":"nftset"'
assert_contains "$tmpdir/lpr-cli-diag.json" '"china_list_version"'
assert_contains "$tmpdir/lpr-cli-diag.json" '"china_list_entries"'
assert_not_contains "$tmpdir/lpr-cli-diag.json" '"backend_error"'

PATH="$tmpdir/min-bin" LPR_BACKEND=auto LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan \
	/bin/sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > "$tmpdir/lpr-cli-diag-fail.json"
assert_contains "$tmpdir/lpr-cli-diag-fail.json" '"backend":"unknown"'
assert_contains "$tmpdir/lpr-cli-diag-fail.json" '"backend_error":"unable to detect backend"'

assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"luci-app-lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"status"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"logs"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"reload"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"update_chnroute"'

cat > "$tmpdir/mock-service-success" <<'EOF'
#!/bin/sh
case "$1" in
	diagnose)
		printf '{"ok":true,"backend":"nftset"}\n'
		;;
	cleanup|apply)
		exit 0
		;;
	*)
		printf 'unexpected command: %s\n' "$1" >&2
		exit 1
		;;
esac
EOF
chmod +x "$tmpdir/mock-service-success"

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" sh "$rpc" list > "$tmpdir/rpc-list.json"
assert_contains "$tmpdir/rpc-list.json" '"status"'
assert_contains "$tmpdir/rpc-list.json" '"logs"'
assert_contains "$tmpdir/rpc-list.json" '"reload"'
assert_contains "$tmpdir/rpc-list.json" '"update_chnroute"'
assert_contains "$tmpdir/rpc-list.json" '"test_route"'

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" sh "$rpc" call status > "$tmpdir/rpc-status.json"
assert_contains "$tmpdir/rpc-status.json" '"backend":"nftset"'

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" sh "$rpc" call reload > "$tmpdir/rpc-reload-ok.json"
assert_contains "$tmpdir/rpc-reload-ok.json" '"ok":true'

cat > "$tmpdir/mock-updater-ok" <<'EOF'
#!/bin/sh
printf 'chnroute: updated to version 20260704060757 (4065 entries)\n'
exit 0
EOF
chmod +x "$tmpdir/mock-updater-ok"

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" LPR_RPCD_UPDATER="$tmpdir/mock-updater-ok" \
	sh "$rpc" call update_chnroute > "$tmpdir/rpc-update-ok.json"
assert_contains "$tmpdir/rpc-update-ok.json" '"ok":true'
assert_contains "$tmpdir/rpc-update-ok.json" "updated to version 20260704060757"

cat > "$tmpdir/mock-updater-fail" <<'EOF'
#!/bin/sh
printf 'chnroute: failed to fetch version\n' >&2
exit 1
EOF
chmod +x "$tmpdir/mock-updater-fail"

if LPR_RPCD_SERVICE="$tmpdir/mock-service-success" LPR_RPCD_UPDATER="$tmpdir/mock-updater-fail" \
	sh "$rpc" call update_chnroute > "$tmpdir/rpc-update-fail.json"; then
	fail "rpc update_chnroute unexpectedly succeeded"
fi
assert_contains "$tmpdir/rpc-update-fail.json" '"ok":false'
assert_contains "$tmpdir/rpc-update-fail.json" "failed to fetch version"

cat > "$tmpdir/mock-service-cleanup-fail" <<'EOF'
#!/bin/sh
case "$1" in
	diagnose)
		printf '{"ok":true,"backend":"nftset"}\n'
		;;
	cleanup)
		printf 'cleanup failed\n' >&2
		exit 1
		;;
	apply)
		exit 0
		;;
	*)
		printf 'unexpected command: %s\n' "$1" >&2
		exit 1
		;;
esac
EOF
chmod +x "$tmpdir/mock-service-cleanup-fail"

if LPR_RPCD_SERVICE="$tmpdir/mock-service-cleanup-fail" sh "$rpc" call reload > "$tmpdir/rpc-reload-cleanup-fail.json" 2>"$tmpdir/rpc-reload-cleanup-fail.err"; then
	fail "rpc reload unexpectedly succeeded on cleanup failure"
fi
assert_contains "$tmpdir/rpc-reload-cleanup-fail.json" '"ok":false'
assert_contains "$tmpdir/rpc-reload-cleanup-fail.json" '"error":"cleanup failed"'

cat > "$tmpdir/mock-service-fail" <<'EOF'
#!/bin/sh
case "$1" in
	diagnose|cleanup)
		exit 0
		;;
	apply)
		printf 'apply failed\n' >&2
		exit 1
		;;
	*)
		printf 'unexpected command: %s\n' "$1" >&2
		exit 1
		;;
esac
EOF
chmod +x "$tmpdir/mock-service-fail"

if LPR_RPCD_SERVICE="$tmpdir/mock-service-fail" sh "$rpc" call reload > "$tmpdir/rpc-reload-fail.json" 2>"$tmpdir/rpc-reload-fail.err"; then
	fail "rpc reload unexpectedly succeeded"
fi
assert_contains "$tmpdir/rpc-reload-fail.json" '"ok":false'
assert_contains "$tmpdir/rpc-reload-fail.json" '"error":"apply failed"'
