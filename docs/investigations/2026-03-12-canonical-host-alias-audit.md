# Canonical Host Alias Audit (2026-03-12)

## Goal
Remove active DX contract usage of raw OS hostnames for 1Password token filenames and standardize on canonical host aliases:
- `macmini`
- `homedesktop-wsl`
- `epyc6`
- `epyc12`

## Findings

### Fixed in this change
- token creation now uses canonical host alias naming instead of raw `hostname`
- OP token loaders now prefer canonical alias paths and only use raw-hostname paths as legacy fallback
- active onboarding docs and runbooks no longer teach `op-$(hostname)-token` as the primary contract
- nightly dispatcher now uses shared auth loading rather than a hardcoded `op-macmini-token` path
- cross-VM verification docs no longer describe macmini token naming as legacy or epyc6 as lacking OP token support

### Intentionally left in place
- raw hostname detection inside `scripts/canonical-targets.sh`
  - needed to map opaque provider hostnames to canonical aliases when Tailscale/MagicDNS is unavailable
- raw hostname mentions in telemetry, diagnostics, and evidence scripts
  - these are identifiers for logs/status, not token-file contracts
- legacy fallback support for `op_token` and raw-hostname-based filenames in auth loaders
  - retained temporarily for safe migration and recovery

## Resulting contract
Active DX auth paths should use canonical alias filenames:
- `~/.config/systemd/user/op-macmini-token`
- `~/.config/systemd/user/op-homedesktop-wsl-token`
- `~/.config/systemd/user/op-epyc6-token`
- `~/.config/systemd/user/op-epyc12-token`

Encrypted equivalents follow the same naming with `.cred` suffix.
