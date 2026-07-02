#!/bin/sh
set -eu

. ./tests/lib/assert.sh

menu=root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json
assert_file_exists "$menu"
assert_contains "$menu" "admin/services/lan-proxy-route"
assert_contains "$menu" "\"path\": \"lan-proxy-route/overview\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/settings\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/dns\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/clients\""
assert_contains "$menu" "\"path\": \"lan-proxy-route/rules\""
assert_not_contains "$menu" "view/lan-proxy-route/overview"
assert_not_contains "$menu" "view/lan-proxy-route/settings"
assert_not_contains "$menu" "view/lan-proxy-route/dns"
assert_not_contains "$menu" "view/lan-proxy-route/clients"
assert_not_contains "$menu" "view/lan-proxy-route/rules"

for view in overview settings dns clients rules; do
	file="root/www/luci-static/resources/view/lan-proxy-route/$view.js"
	assert_file_exists "$file"
	assert_contains "$file" "'require view';"
	assert_contains "$file" "return view.extend({"
done

assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "'require rpc';"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/overview.js "'require uci';"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "'enabled'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/dns.js "'hijack_53'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/clients.js "'mode'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "fake_ip_cidr"
