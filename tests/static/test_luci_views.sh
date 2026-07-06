#!/bin/sh
set -eu

. ./tests/lib/assert.sh

menu=root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json
assert_file_exists "$menu"
assert_contains "$menu" "admin/services/lan-proxy-route"
assert_contains "$menu" "\"path\": \"lan-proxy-route/overview\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/settings\""
assert_not_contains "$menu" "\"path\": \"lan-proxy-route/dns\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/clients\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/rules\""
assert_not_contains "$menu" "view/lan-proxy-route/overview"
assert_not_contains "$menu" "view/lan-proxy-route/settings"
assert_not_contains "$menu" "view/lan-proxy-route/clients"
assert_not_contains "$menu" "view/lan-proxy-route/rules"

[ ! -f root/www/luci-static/resources/view/lan-proxy-route/dns.js ] || fail "dns view still exists"
assert_file_exists root/www/luci-static/resources/lan-proxy-route/apply.js
assert_contains root/www/luci-static/resources/lan-proxy-route/apply.js "baseclass.extend"
assert_contains root/www/luci-static/resources/lan-proxy-route/apply.js "saveAndApply"

for view in overview settings clients rules; do
	file="root/www/luci-static/resources/view/lan-proxy-route/$view.js"
	assert_file_exists "$file"
	assert_contains "$file" "'require view';"
	assert_contains "$file" "return view.extend({"
done

assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "'require rpc';"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "'require uci';"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "callStatus().catch(function()"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "check_chnroute"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "资源管理"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "检查更新"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "自定义更新源"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "chnroute_url"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "handleSaveApply"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/clients.js "handleSaveApply"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "handleSaveApply"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "or(ip4addr,cidr4)"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "dns_hijack_present"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "dnsmasq"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "dns_mode"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "fake_ip_cidr"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "dns_port"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/clients.js "'mode'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "'bypass'"
assert_not_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "fake_ip_cidr"
