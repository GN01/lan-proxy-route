#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/diagnostics.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/min-bin"
ln -s /bin/cat "$tmpdir/min-bin/cat"

json="$(lpr_diag_json nftset 192.168.1.2 br-lan 0x210 210 10210)"
printf '%s\n' "$json" > "$tmpdir/lpr-diag.json"
assert_contains "$tmpdir/lpr-diag.json" '"backend":"nftset"'
assert_contains "$tmpdir/lpr-diag.json" '"x86_ip":"192.168.1.2"'
assert_contains "$tmpdir/lpr-diag.json" '"lan_if":"br-lan"'
assert_contains "$tmpdir/lpr-diag.json" '"mark":"0x210"'
assert_contains "$tmpdir/lpr-diag.json" '"table":"210"'
assert_contains "$tmpdir/lpr-diag.json" '"priority":"10210"'

rpc=./root/usr/libexec/rpcd/lan-proxy-route
assert_file_exists "$rpc"
sh -n "$rpc"

LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan \
	sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > "$tmpdir/lpr-cli-diag.json"
assert_contains "$tmpdir/lpr-cli-diag.json" '"backend":"nftset"'
assert_contains "$tmpdir/lpr-cli-diag.json" '"domain_set_available"'
assert_not_contains "$tmpdir/lpr-cli-diag.json" '"backend_error"'

PATH="$tmpdir/min-bin" LPR_BACKEND=auto LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan \
	/bin/sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > "$tmpdir/lpr-cli-diag-fail.json"
assert_contains "$tmpdir/lpr-cli-diag-fail.json" '"backend":"unknown"'
assert_contains "$tmpdir/lpr-cli-diag-fail.json" '"backend_error":"unable to detect backend"'

assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"luci-app-lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"status"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"reload"'

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
assert_contains "$tmpdir/rpc-list.json" '"reload"'
assert_contains "$tmpdir/rpc-list.json" '"test_route"'

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" sh "$rpc" call status > "$tmpdir/rpc-status.json"
assert_contains "$tmpdir/rpc-status.json" '"backend":"nftset"'

LPR_RPCD_SERVICE="$tmpdir/mock-service-success" sh "$rpc" call reload > "$tmpdir/rpc-reload-ok.json"
assert_contains "$tmpdir/rpc-reload-ok.json" '"ok":true'

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
