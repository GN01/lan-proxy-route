#!/bin/sh
set -eu

. ./tests/lib/assert.sh

for file in \
	root/etc/init.d/lan-proxy-route \
	root/usr/share/lan-proxy-route/common.sh \
	root/usr/share/lan-proxy-route/lan-proxy-route.sh \
	root/usr/share/lan-proxy-route/update-chnroute.sh \
	root/usr/share/lan-proxy-route/diagnostics.sh \
	root/usr/share/lan-proxy-route/backends/nft.sh \
	root/usr/share/lan-proxy-route/backends/ipset.sh \
	root/usr/libexec/rpcd/lan-proxy-route
do
	assert_file_exists "$file"
	sh -n "$file"
done
