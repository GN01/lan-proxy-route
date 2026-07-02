Status: done
Commits created: effa722 feat: add service orchestration
Test summary: `sh tests/run.sh` passes on the committed tree, including static skeleton, common, dnsmasq, nft, ipset, and new service CLI coverage.
Concerns: none
Report file: /Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-6-report.md

Status: done
Commits created: 3496a73 fix: harden service apply and cleanup orchestration
Test summary: Added regression coverage for real cleanup execution, dnsmasq runtime-file writes during `apply`, ipset DNS firewall teardown, and LAN_IF-aware ipset cleanup; `sh tests/run.sh` passes.
Concerns: none
Report file: /Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-6-report.md

Status: done
Commits created: 292ceca fix: harden service dnsmasq lifecycle
Test summary: Added coverage for `start_service` reloading `dnsmasq`, `status_service` calling `$SERVICE diagnose`, and `cleanup` removing the service-owned runtime dnsmasq file in dry-run and real execution; `sh tests/run.sh` passes.
Concerns: none
Report file: /Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-6-report.md

Status: done
Commits created: b9606c5 fix: expose init diagnose command
Test summary: Added regression coverage that the init script exposes standalone `diagnose`, defines `diagnose()`, and routes both init entry points to `$SERVICE diagnose`; `sh tests/run.sh` passes.
Concerns: none
Report file: /Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-6-report.md

Status: done
Commits created: test: cover nftset cleanup dns firewall teardown
Test summary: Added Task 6 regression coverage proving nftset service cleanup emits and executes teardown for both `dns_hijack` and `dns_dot_block`; `sh tests/run.sh` passes.
Concerns: none
Report file: /Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-6-report.md
