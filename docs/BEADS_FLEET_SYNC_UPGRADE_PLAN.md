# Plan: Beads Fleet Sync Upgrade (Dolt Native Remotes)

## Problem Statement
The current "JSONL-over-Git" hybrid sync is fragile. It relies on mtime and hash checks to trigger auto-imports after Git operations, leading to "issue resurrection" bugs and lock contention on high-load VMs like epyc12.

## Proposed Solution: Dolt Native Remotes
Replace Git-based JSONL sync with native Dolt push/pull to a centralized remote.

### Phase 1: SSH Remote on epyc12 (Quick Fix)
- **Infrastructure:** Use existing SSH trust on epyc12.
- **Effort:** Low (5 mins).
- **Setup:**
  1. ssh epyc12 "mkdir -p ~/bd-remote && cd ~/bd-remote && dolt init --bare"
  2. cd ~/bd/.beads/dolt/beads_bd && dolt remote add origin ssh://feng@epyc12/home/feng/bd-remote
  3. dolt push origin main
- **Sync Mode:** Set sync.mode: dolt-native in .beads/config.yaml.

### Phase 2: S3-Compatible Remote on Railway (Long-Term)
- **Infrastructure:** MinIO on Railway or Cloudflare R2.
- **Effort:** Moderate (30 mins).
- **Benefits:** Highest robustness; handles multi-agent concurrency natively; no VM maintenance.
- **Setup:**
  1. Deploy MinIO/R2.
  2. dolt remote add fleet-cloud aws://beads-storage/repo --endpoint=https://your-endpoint
  3. Update dx-runner preflight to perform dolt pull fleet-cloud main.

## Infrastructure Analysis

| Target | Pros | Cons |
| :--- | :--- | :--- |
| **epyc12 (SSH)** | Zero cost; fast local network; already trusted. | Single point of failure; requires VM uptime. |
| **Railway (S3)** | Fully managed; high availability; zero cognitive load. | Adds dependency on external cloud; minor cost. |

**Recommendation:** For the solo founder (Nakomi Protocol), **Railway/S3** is the superior long-term choice as it eliminates the "is the VM running?" mental tax. Start with SSH for immediate stabilization.

## Success Criteria
- [ ] bd sync is replaced by dolt push/pull in all orchestrators.
- [ ] No more "issue resurrection" logs in daemon.log.
- [ ] bd dolt test passes across all fleet nodes against the new remote.
