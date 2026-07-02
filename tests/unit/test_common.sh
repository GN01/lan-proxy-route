#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh

assert_ipv4_preserves_positional_params() {
	set -- alpha beta
	lpr_is_ipv4 192.168.1.2 || fail "valid IPv4 rejected"
	assert_eq "alpha beta" "$*"
}

make_bin_dir() {
	dir="$(mktemp -d)"
	for bin in "$@"; do
		printf '#!/bin/sh\nexit 0\n' > "$dir/$bin"
		chmod +x "$dir/$bin"
	done
	printf '%s\n' "$dir"
}

lpr_cmd_test_output="$(LPR_DRY_RUN=1 lpr_cmd echo hello world)"

lpr_is_ipv4 192.168.1.2 || fail "valid IPv4 rejected"
lpr_is_ipv4 0.0.0.0 || fail "zero IPv4 rejected"
lpr_is_ipv4 255.255.255.255 || fail "broadcast IPv4 rejected"
if lpr_is_ipv4 999.1.1.1; then fail "invalid IPv4 accepted"; fi
if lpr_is_ipv4 abc.def.ghi.jkl; then fail "text IPv4 accepted"; fi
assert_ipv4_preserves_positional_params

lpr_is_cidr 192.168.1.0/24 || fail "valid CIDR rejected"
lpr_is_cidr 198.18.0.0/15 || fail "fake CIDR rejected"
if lpr_is_cidr 192.168.1.0/33; then fail "invalid CIDR prefix accepted"; fi
if lpr_is_cidr 192.168.1.1; then fail "plain IP accepted as CIDR"; fi

lpr_cidr_contains_ipv4 192.168.50.0/24 192.168.50.10 || fail "CIDR containment rejected covered host"
if lpr_cidr_contains_ipv4 192.168.60.0/24 192.168.50.20; then fail "CIDR containment accepted uncovered host"; fi
lpr_cidr_contains_cidr 192.168.0.0/16 192.168.50.0/24 || fail "CIDR containment rejected covered CIDR"
if lpr_cidr_contains_cidr 192.168.60.0/24 192.168.50.0/24; then fail "CIDR containment accepted uncovered CIDR"; fi

lpr_is_domain google.com || fail "valid domain rejected"
lpr_is_domain .youtube.com || fail "leading dot domain rejected"
if lpr_is_domain ..example.com; then fail "double-dot domain accepted"; fi
if lpr_is_domain "bad domain.com"; then fail "domain with space accepted"; fi
if lpr_is_domain "-bad.example"; then fail "leading dash accepted"; fi
if lpr_is_domain foo.bar-; then fail "terminal dash accepted"; fi
if lpr_is_domain foo.bar-baz-; then fail "terminal dash label accepted"; fi

lpr_is_uint 210 || fail "valid uint rejected"
if lpr_is_uint abc; then fail "text uint accepted"; fi

lpr_is_mark 0x210 || fail "hex mark rejected"
lpr_is_mark 528 || fail "decimal mark rejected"
if lpr_is_mark 0xzz; then fail "invalid hex mark accepted"; fi

assert_eq "echo hello world" "$lpr_cmd_test_output"

nft_fw4_dir="$(make_bin_dir nft fw4)"
nft_ipset_dir="$(make_bin_dir nft ipset)"

assert_eq nftset "$(PATH="$nft_fw4_dir" lpr_detect_backend auto)"
assert_eq ipset "$(PATH="$nft_ipset_dir" lpr_detect_backend auto)"

assert_eq nftset "$(PATH="$nft_ipset_dir" lpr_detect_backend nftset)"
assert_eq ipset "$(PATH="$nft_fw4_dir" lpr_detect_backend ipset)"
