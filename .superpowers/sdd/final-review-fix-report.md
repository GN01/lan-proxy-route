# Final Review Fix Report

## Findings Addressed

- Critical 1: The service CLI now loads `/etc/config/lan_proxy_route` by default, supports `LPR_CONFIG` for tests, validates loaded values before runtime commands, honors `global.enabled`, and keeps environment overrides usable for local tests.
- Critical 2: The nft backend now renders executable `nft add ...` command lines instead of a raw multi-line ruleset, and apply-level tests prove raw ruleset lines are not sent to the command runner.
- Critical 3: Cleanup now deletes only the owned default route via the configured X86 IP and LAN interface. nft/ipset cleanup renderers require those values and tests reject `ip route flush table`.
- Important 1: Access allow/block and bypass entries are rendered into nft/ipset sets. Bypass population includes configured CIDRs plus anti-loop X86 and DNS server IPs.
- Important 2: Enabled `config list` sections are read from UCI and carry `role`, `source`, `dns_result`, and `dns_upstream`; mixed configs can render fake-ip and real-ip list behavior together.
- Important 3: Diagnostics now report dependency availability, dnsmasq config presence, backend table/set presence, policy rule/route presence, DNS hijack/DoT presence, and X86 reachability. rpcd `test_route` delegates to the CLI route lookup instead of returning a placeholder.
- Important 4: Makefile dependencies now include the primary nft/firewall4 path and the advertised ipset/iptables compatibility path, with a QSDK package-name note in README.

## Tests Added/Changed

- Added `tests/unit/test_final_review_regressions.sh` covering UCI-driven render, disabled render, nft apply command-runner safety, safe cleanup, access/bypass set population, mixed list DNS behavior, diagnostics fields, rpcd `test_route`, and package deps.
- Updated nft/ipset/backend idempotency tests to require owned-route deletion and reject `ip route flush table`.
- Updated nft backend tests for executable `nft add ...` output.

## TDD RED/GREEN Evidence

RED:

```sh
sh tests/unit/test_final_review_regressions.sh
# failed with: unable to detect backend

sh tests/unit/test_nft_backend.sh
# failed with missing: ip route del default via 192.168.1.2 dev br-lan table 210 2>/dev/null || true

sh tests/unit/test_ipset_backend.sh
# failed with missing: ip route del default via 192.168.1.2 dev br-lan table 210 2>/dev/null || true

sh tests/unit/test_idempotency_contract.sh
# failed with missing nft owned-route deletion
```

GREEN:

```sh
sh tests/unit/test_final_review_regressions.sh
sh tests/unit/test_nft_backend.sh
sh tests/unit/test_ipset_backend.sh
sh tests/unit/test_service_cli.sh
sh tests/unit/test_dnsmasq.sh
sh tests/unit/test_diagnostics.sh
sh tests/unit/test_idempotency_contract.sh
# all passed

sh tests/run.sh
# passed:
# tests/static/test_luci_views.sh
# tests/static/test_package_skeleton.sh
# tests/static/test_shell_syntax.sh
# tests/unit/test_common.sh
# tests/unit/test_diagnostics.sh
# tests/unit/test_dnsmasq.sh
# tests/unit/test_final_review_regressions.sh
# tests/unit/test_idempotency_contract.sh
# tests/unit/test_ipset_backend.sh
# tests/unit/test_nft_backend.sh
# tests/unit/test_service_cli.sh
```

## Files Changed

- `Makefile`
- `README.md`
- `root/usr/libexec/rpcd/lan-proxy-route`
- `root/usr/share/lan-proxy-route/common.sh`
- `root/usr/share/lan-proxy-route/diagnostics.sh`
- `root/usr/share/lan-proxy-route/dnsmasq.sh`
- `root/usr/share/lan-proxy-route/lan-proxy-route.sh`
- `root/usr/share/lan-proxy-route/backends/nft.sh`
- `root/usr/share/lan-proxy-route/backends/ipset.sh`
- `tests/unit/test_final_review_regressions.sh`
- `tests/unit/test_idempotency_contract.sh`
- `tests/unit/test_ipset_backend.sh`
- `tests/unit/test_nft_backend.sh`

## Remaining Concerns

- Diagnostics set entry counts are reported as `"unknown"` when portable shell parsing would be unreliable; presence checks are implemented and robust when commands are unavailable.
