Status: completed
Commits created: 1 (`1d774a0` feat: add diagnostics rpc bridge)
Test summary: `sh tests/run.sh` failed first on missing `root/usr/share/lan-proxy-route/diagnostics.sh`, then passed the full local suite after implementation.
Concerns: none
Report file: `/Users/gin/data/GitHub/ipset-luci/.worktrees/feature-lan-proxy-route/.superpowers/sdd/task-7-report.md`

Fix follow-up after review:
- Corrected rpcd `reload` so it now returns `{"ok":true}` only when both `cleanup` and `apply` succeed; it returns JSON failure with exit 1 when either stage fails.
- Updated CLI `diagnose` to surface backend auto-detection failure via `"backend_error":"unable to detect backend"` while preserving the normal backend field for successful detection.
- Expanded `tests/unit/test_diagnostics.sh` to exercise rpcd `list`, `call status`, successful `call reload`, and failing `call reload`, alongside the new diagnose failure case.
- Diagnostics remain intentionally minimal in Task 7: they report service/backend/config presence only. Richer route/set/reachability inspection is deferred to later integration work.

Verification:
- `sh tests/run.sh`
