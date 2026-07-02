# Final Review Fix 2 Report

## Findings Addressed

- Critical 1: nft set element rendering now removes exact duplicates, skips IPv4 host entries covered by a CIDR in the same set, and skips narrower CIDR entries covered by broader CIDRs. This covers default-style bypass overlap (`192.168.0.0/16` with `192.168.1.2`) and allowlist overlap (`192.168.50.0/24` with `192.168.50.10`) without changing ipset rendering behavior.
- Important 1: Default singleton UCI sections are now named: `global`, `dns`, `access`, and `bypass`. The existing parser continues to handle named sections by section type.
- Important 2: Runtime apply writes a service state file with backend, mark, table, priority, X86 IP, and LAN interface. Cleanup renders current cleanup plus previous-state cleanup when the persisted tuple differs, then removes the state file.
- Important 3: rpcd `reload` now mirrors init behavior after successful apply by reloading dnsmasq and firewall with tolerant `|| true` behavior and test overrides.
- Important 4: rpcd `test_route` extracts `dst` from JSON object arguments while retaining raw-argument compatibility.

## Tests Added/Changed

- Updated `tests/static/test_package_skeleton.sh` for named singleton sections.
- Added common helper coverage for IPv4 host and CIDR containment.
- Updated `tests/unit/test_final_review_regressions.sh` for nft host/CIDR overlap, default bypass overlap, exact duplicate host suppression, rpcd JSON `test_route`, and rpcd reload side effects.
- Updated `tests/unit/test_service_cli.sh` for state-file writes and previous runtime tuple cleanup.

## TDD RED/GREEN Evidence

RED:

```sh
sh tests/static/test_package_skeleton.sh
# failed: root/etc/config/lan_proxy_route does not contain: config global 'global'

sh tests/unit/test_final_review_regressions.sh
# failed: render.out unexpectedly contains: nft add element inet lan_proxy_route clients_v4 { 192.168.50.10 }

sh tests/unit/test_service_cli.sh
# failed: exec.log does not contain previous-state route cleanup for 192.168.33.2/br-old/table 333

sh tests/unit/test_common.sh
# failed: CIDR containment accepted uncovered host

sh tests/unit/test_common.sh
# failed: lpr_cidr_contains_cidr: command not found

sh tests/unit/test_final_review_regressions.sh
# failed: default-overlap.out unexpectedly contains covered narrower bypass CIDR 192.168.1.0/24
```

GREEN:

```sh
sh tests/unit/test_common.sh
sh tests/static/test_package_skeleton.sh
sh tests/unit/test_final_review_regressions.sh
sh tests/unit/test_service_cli.sh
# all passed

sh tests/static/test_luci_views.sh
sh tests/unit/test_diagnostics.sh
sh tests/unit/test_nft_backend.sh
sh tests/unit/test_idempotency_contract.sh
sh tests/unit/test_ipset_backend.sh
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

- `root/etc/config/lan_proxy_route`
- `root/usr/libexec/rpcd/lan-proxy-route`
- `root/usr/share/lan-proxy-route/common.sh`
- `root/usr/share/lan-proxy-route/lan-proxy-route.sh`
- `root/usr/share/lan-proxy-route/backends/nft.sh`
- `tests/static/test_package_skeleton.sh`
- `tests/unit/test_common.sh`
- `tests/unit/test_final_review_regressions.sh`
- `tests/unit/test_service_cli.sh`
- `.superpowers/sdd/final-review-fix-2-report.md`

## Remaining Concerns

- None.
