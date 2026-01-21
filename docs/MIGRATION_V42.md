# V4.2 Migration Guide

⚠️ **V4.1 (Plaintext Tokens) is DEPRECATED**

V4.1 stored service account tokens in plaintext files (`~/.config/op-service-tokens/`) with 600 permissions. While this provided basic isolation, V4.2 introduces encrypted credentials for superior security.

## Architecture Changes

| Feature | V4.1 | V4.2 |
|---------|------|------|
| **Storage** | Plaintext File | Encrypted Credential |
| **Path** | `~/.config/op-service-tokens/` | `~/.config/systemd/user/op_token.cred` |
| **Systemd** | `EnvironmentFile` | `LoadCredentialEncrypted` (or `LoadCredential`) |
| **Encryption** | None | AES-256-GCM |

## Migration Steps

### 1. Run Migration Script
This script detects your V4.1 token, encrypts it, and backs up the old file.

```bash
~/agent-skills/scripts/migrate-to-v4.2.sh
```

### 2. Update Systemd Services
Update your services to use the new credential loading mechanism.

```bash
~/agent-skills/scripts/update-services-v42.sh
```

### 3. Verify
Ensure services are running and the credential is readable by the service.

```bash
~/agent-skills/scripts/verify-all-vms-v42.sh
```

### 4. Cleanup (Optional)
Once verified, remove the V4.1 backup files.

```bash
rm -rf ~/.config/op-service-tokens/
```

## Rollback

If V4.2 services fail to start:

1. Restore the V4.1 service files:
   ```bash
   cp ~/.config/systemd/user/opencode.service.v41.backup ~/.config/systemd/user/opencode.service
   ```
2. Restore the plaintext token:
   ```bash
   mkdir -p ~/.config/op-service-tokens/
   cp <backup_location> ~/.config/op-service-tokens/service-account.token
   ```
3. Reload systemd:
   ```bash
   systemctl --user daemon-reload
   ```
