# Beads Fleet Sync Upgrade V2 (Railway MinIO + Dolt Native)

## Metadata
- Feature-Key: `bd-aggg.1`
- Epic: `bd-aggg` (`BEADS_FLEET_SYNC_V2_RAILWAY_MINIO_CUTOVER`)
- Last updated: 2026-02-27
- Owners: Infra/DevOps
- Scope: Canonical Beads repo `~/bd` across `macmini`, `epyc12`, `epyc6`, `homedesktop-wsl`

## 1) Outcome and Success Definition

Migrate fleet sync from JSONL-over-Git behavior to Dolt-native remote sync backed by Railway-hosted MinIO (S3-compatible) while keeping local Dolt server mode per host.

Success is reached only when all conditions hold:
1. All hosts have `sync.mode = dolt-native` in Beads config.
2. All hosts can `dolt pull` and `dolt push` against a single MinIO remote.
3. Cross-host issue totals and spot-checked records are consistent.
4. No "issue resurrection" incidents during a 7-day stabilization window.
5. Rollback drill completed and documented with measured RTO/RPO.

## 2) Non-Goals

1. Replacing local Dolt server mode with a central SQL server.
2. Changing Beads issue taxonomy or workflow semantics.
3. Replatforming all DX automation in this change.

## 3) Required Inputs (Do Not Start Without These)

Fill in all values before implementation:

```bash
export RAILWAY_PROJECT_ID="<project-id>"
export RAILWAY_ENV="<environment-name>"
export MINIO_SERVICE="<railway-service-name>"
export MINIO_ENDPOINT="https://<minio-endpoint>"
export MINIO_BUCKET="beads-storage"
export MINIO_DB_PATH="beads_bd"
export MINIO_AWS_REGION="us-east-1"

# Secrets are sourced from 1Password references; do not hardcode.
export AWS_ACCESS_KEY_ID="$(op read 'op://dev/Agent-Secrets-Production/BEADS_MINIO_ACCESS_KEY')"
export AWS_SECRET_ACCESS_KEY="$(op read 'op://dev/Agent-Secrets-Production/BEADS_MINIO_SECRET_KEY')"
```

Required access:
1. Railway project admin permissions.
2. 1Password service account read access to MinIO keys.
3. SSH access to all canonical hosts.
4. `bd`, `dolt`, `jq`, `railway`, and `op` installed on operator host.

## 4) Architecture Decision

Chosen target: Railway MinIO S3 remote with local Dolt per-host.

Why:
1. Removes VM uptime dependency as sync source of truth.
2. Preserves host-local performance and current Dolt server contract.
3. Reduces cognitive load and operator intervention for a solo founder workflow.

Data path after migration:
1. Host-local `bd` mutations update local Dolt database.
2. Hosts sync state through `dolt pull` / `dolt push` to MinIO remote.
3. Preflight verifies remote connectivity before orchestration waves.

## 5) Beads Execution Plan (Self-Documented)

Epic and tasks are already created:

| ID | Type | Title | Depends On (blocks) | Deliverable |
|---|---|---|---|---|
| `bd-aggg` | epic | BEADS_FLEET_SYNC_V2_RAILWAY_MINIO_CUTOVER | - | End-to-end migration complete |
| `bd-aggg.1` | task | Define V2 cutover invariants and migration gates | - | This V2 plan + go/no-go gates |
| `bd-aggg.2` | task | Provision Railway MinIO and hardened S3 endpoint | `bd-aggg.1` | Reachable MinIO endpoint + bucket policy |
| `bd-aggg.3` | task | Configure credentials and secret distribution | `bd-aggg.1` | Secret flow + rotation procedure |
| `bd-aggg.4` | feature | Integrate Dolt remote sync into dx preflight/orchestrators | `bd-aggg.1`, `bd-aggg.2`, `bd-aggg.3` | Tooling + runbook updates |
| `bd-aggg.5` | task | Canary cutover on epyc12 with validation matrix | `bd-aggg.4` | Canary evidence + validation report |
| `bd-aggg.6` | task | Fleet rollout to remaining hosts | `bd-aggg.5` | All hosts migrated and validated |
| `bd-aggg.7` | task | Rollback drill + incident runbook hardening | `bd-aggg.6` | Tested rollback playbook |
| `bd-aggg.8` | task | Disable legacy JSONL-over-Git paths and publish closeout | `bd-aggg.6`, `bd-aggg.7` | Legacy path disabled + closeout report |

Operational rule:
1. Do not start a blocked task until all blockers are closed.
2. Keep evidence in each subtask comment: command, timestamp, output summary, decision.

## 6) Runbook: Phase-by-Phase Implementation

### Phase 0: Preflight and Freeze

Objective: lock current state and prevent concurrent writes during cutover.

Steps:
1. Verify canonical Beads health:

```bash
cd ~/bd
bd dolt test --json
bd status --json | jq -c '.summary'
```

2. Validate host health snapshots:

```bash
for host in macmini epyc12 epyc6 homedesktop-wsl; do
  ssh "$host" 'cd ~/bd && bd dolt test --json && bd status --json | jq -c ".summary"'
done
```

3. Freeze orchestrators and background mutators (cron/systemd jobs that mutate Beads).
4. Create immutable backup per host:

```bash
for host in macmini epyc12 epyc6 homedesktop-wsl; do
  ssh "$host" 'cd ~/bd/.beads && ts=$(date +%Y%m%d%H%M%S) && tar -czf "$HOME/bd-backup-$ts.tgz" dolt issues.jsonl deletions.jsonl 2>/dev/null || tar -czf "$HOME/bd-backup-$ts.tgz" dolt'
done
```

Gate to proceed:
1. Freeze confirmed.
2. Backup artifact created on each host.
3. Baseline issue summary captured.

### Phase 1: Provision Railway MinIO

Objective: create hardened S3-compatible endpoint for Dolt remote.

Steps:
1. Provision MinIO service in Railway project/environment.
2. Create bucket `${MINIO_BUCKET}` and namespace path `${MINIO_DB_PATH}`.
3. Generate access key pair dedicated to Beads sync.
4. Enforce private bucket access and TLS-only endpoint.
5. Record endpoint and credentials in 1Password; never commit secrets.

Verification:

```bash
railway status
railway service

# Endpoint reachable from operator host
curl -sSf "${MINIO_ENDPOINT}" >/dev/null
```

Gate to proceed:
1. Endpoint reachable.
2. Credentials valid.
3. Policy enforces least privilege.

### Phase 2: Configure Secrets and Local Host Environment

Objective: ensure all hosts can authenticate to MinIO remote using env creds.

On each host (`macmini`, `epyc12`, `epyc6`, `homedesktop-wsl`):

```bash
# Example: inject via secure runtime env mechanism; do not store in repo files.
export AWS_ACCESS_KEY_ID="$(op read 'op://dev/Agent-Secrets-Production/BEADS_MINIO_ACCESS_KEY')"
export AWS_SECRET_ACCESS_KEY="$(op read 'op://dev/Agent-Secrets-Production/BEADS_MINIO_SECRET_KEY')"
export AWS_REGION="${MINIO_AWS_REGION}"
```

Set Beads sync mode once per host:

```bash
cd ~/bd
bd config set sync.mode dolt-native
bd config get sync.mode
```

Gate to proceed:
1. `sync.mode` returns `dolt-native` on all hosts.
2. Credential source is 1Password-backed and not persisted in git-tracked files.

### Phase 3: Configure Dolt Remote (Canary Host First)

Objective: validate remote config with lowest blast radius before fleet rollout.

Canary host: `epyc12`

```bash
cd ~/bd/.beads/dolt/beads_bd

# Idempotent remote setup
if dolt remote | grep -q '^fleet-cloud$'; then
  dolt remote remove fleet-cloud
fi

dolt remote add \
  --aws-region "${MINIO_AWS_REGION}" \
  --aws-creds-type env \
  fleet-cloud \
  "aws://${MINIO_BUCKET}/${MINIO_DB_PATH}"

# First push establishes branch if needed
dolt push -u fleet-cloud main

# Pull to ensure read path works
dolt pull fleet-cloud main --ff-only
```

Gate to proceed:
1. Push and pull both succeed on canary.
2. `dolt remote -v` shows `fleet-cloud`.

### Phase 4: Canary Validation Matrix (epyc12)

Objective: prove functional correctness before fleet wave.

Run and capture evidence:

```bash
cd ~/bd
bd status --json | jq -c '.summary'
bd list --status open --limit 20 >/tmp/bd-open-sample.txt

# Mutation test
bd create --title "Canary validation marker" --type task --priority 3 --description "Temporary marker for MinIO sync validation" --json | jq -r '.id' > /tmp/canary_marker_id.txt
marker_id=$(cat /tmp/canary_marker_id.txt)

# Ensure marker persisted remotely
cd ~/bd/.beads/dolt/beads_bd
dolt push fleet-cloud main

# Verify readable via bd
cd ~/bd
bd show "$marker_id"
```

Cleanup:

```bash
cd ~/bd
bd close "$(cat /tmp/canary_marker_id.txt)" --reason "Canary validation complete"
```

Gate to proceed:
1. Create/read/close path succeeds.
2. No lock contention or divergence symptoms.

### Phase 5: Fleet Rollout (Waves)

Objective: migrate remaining hosts with controlled blast radius.

Wave order:
1. `macmini`
2. `epyc6`
3. `homedesktop-wsl`

Per-host commands mirror canary Phase 3 + health validation.

Per-host validation:

```bash
ssh <host> 'cd ~/bd && bd dolt test --json && bd status --json | jq -c ".summary"'
ssh <host> 'cd ~/bd/.beads/dolt/beads_bd && dolt pull fleet-cloud main --ff-only && dolt push fleet-cloud main'
```

Cross-host consistency check:

```bash
for host in macmini epyc12 epyc6 homedesktop-wsl; do
  echo "## $host"
  ssh "$host" 'cd ~/bd && bd status --json | jq -c ".summary"'
done
```

Gate to proceed:
1. All hosts pass health checks.
2. Summaries are consistent with expected drift window (normally zero after pull).

### Phase 6: Rollback Drill and Runbook Hardening

Objective: prove recoverability before legacy deprecation.

Rollback triggers:
1. Failed pull/push on two consecutive retries.
2. Cross-host issue count divergence not resolved by pull.
3. Data integrity anomaly (missing/reappearing issues).

Rollback procedure (host-level):

```bash
# 1) Freeze mutations on target host
# 2) Restore latest backup
cd ~/bd/.beads
mv dolt "dolt.bad.$(date +%Y%m%d%H%M%S)"
# restore backed-up dolt directory here

# 3) Restart managed service
# Linux
systemctl --user restart beads-dolt.service
# macOS
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt

# 4) Validate
cd ~/bd
bd dolt test --json
bd status --json | jq -c '.summary'
```

Global rollback option:
1. Re-enable previous sync path toggle (if implemented in tooling).
2. Keep MinIO remote configured but stop using it until root cause resolved.

### Phase 7: Legacy Path Decommission and Closeout

Objective: remove drift vectors from JSONL-over-Git era.

Steps:
1. Remove or gate scripts that perform legacy `bd sync` + Git JSONL propagation for Beads state.
2. Update docs/runbooks to mark Dolt-native MinIO path as canonical.
3. Publish closeout report with:
   - Timeline
   - Incidents (if any)
   - Final host matrix
   - Residual risks

Acceptance gate:
1. 7-day no-resurrection window completed.
2. Epic `bd-aggg` children `bd-aggg.1` ... `bd-aggg.8` closed.

## 7) Validation Checklist (Operator Signoff)

1. `bd dolt test --json` passes on all hosts.
2. `bd status --json` summaries consistent across hosts.
3. `dolt pull fleet-cloud main --ff-only` succeeds on all hosts.
4. `dolt push fleet-cloud main` succeeds on all hosts.
5. Canary mutation test completed and cleaned up.
6. Rollback drill completed with evidence.
7. Legacy sync paths disabled or explicitly break-glass only.

## 8) Risks and Mitigations

1. Credential leakage risk.
Mitigation: `op://` only, no plaintext secrets in repo, key rotation runbook.

2. Endpoint unavailability.
Mitigation: host-local backup + tested rollback + retry budget + freeze gate.

3. Branch/history divergence during cutover.
Mitigation: freeze window, canary first, strict go/no-go gates.

4. Hidden legacy mutators reintroduce drift.
Mitigation: explicit decommission task (`bd-aggg.8`) and verification grep of legacy paths.

## 9) Operator Notes

1. Run mutating Beads commands from canonical `~/bd` only.
2. Keep one Dolt server process per host.
3. Never skip freeze + backup + validation gates.
4. Capture evidence in Beads comments for each subtask.
