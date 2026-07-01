#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/diagnostics.sh

json="$(lpr_diag_json nftset 192.168.1.2 br-lan 0x210 210 10210)"
printf '%s\n' "$json" > /tmp/lpr-diag.json
assert_contains /tmp/lpr-diag.json '"backend":"nftset"'
assert_contains /tmp/lpr-diag.json '"x86_ip":"192.168.1.2"'
assert_contains /tmp/lpr-diag.json '"lan_if":"br-lan"'
assert_contains /tmp/lpr-diag.json '"mark":"0x210"'
assert_contains /tmp/lpr-diag.json '"table":"210"'
assert_contains /tmp/lpr-diag.json '"priority":"10210"'

rpc=./root/usr/libexec/rpcd/lan-proxy-route
assert_file_exists "$rpc"
sh -n "$rpc"

LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > /tmp/lpr-cli-diag.json
assert_contains /tmp/lpr-cli-diag.json '"backend":"nftset"'
assert_contains /tmp/lpr-cli-diag.json '"domain_set_available"'

assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"luci-app-lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"status"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"reload"'
