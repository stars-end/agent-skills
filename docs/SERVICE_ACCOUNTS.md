# Service Accounts Guide

## Architecture

This infrastructure uses 1Password Service Accounts to provide secure, non-interactive authentication for systemd services.

### V4.2 Security Model (Current)

**Encrypted Credentials (Recommended)**
- **Format**: `~/.config/systemd/user/op_token.cred`
- **Encryption**: AES-256-GCM via `systemd-creds`
- **Permissions**: 0600 (user read/write only)
- **Decryption**: Runtime only (in-memory) via `LoadCredentialEncrypted` (or `LoadCredential` fallback)
- **At Rest**: Protected by OS-level disk encryption (BitLocker/LUKS) + file permissions.

### V4.1 Model (Deprecated)

**Plaintext Tokens**
- **Format**: `~/.config/op-service-tokens/service-account.token`
- **Security**: Relied solely on 0600 permissions.
- **Status**: **DEPRECATED**. Migrate to V4.2 immediately.

## Rate Limits

1Password service accounts have strict rate limits:
- **Item Read**: ~60 requests/minute
- **Vault List**: ~60 requests/minute

**Optimization Strategy**:
- **Cache IDs**: Cache Vault/Item IDs in env files to avoid `op item list` calls.
- **Batch Access**: Use `op run --` to inject multiple secrets in a single authentication session.

## Setup & Rotation

### Initial Setup
```bash
# 1. Generate token in 1Password (Business Account)
# 2. Run setup script
~/agent-skills/scripts/create-op-credential.sh
```

### Rotation (Every 90 Days)
1. **Generate New Token**: Revoke old token in 1Password, generate new one.
2. **Update Credential**:
   ```bash
   ~/agent-skills/scripts/create-op-credential.sh --force
   ```
3. **Distribute**:
   ```bash
   ~/agent-skills/scripts/distribute-op-credential.sh
   ```
4. **Restart Services**:
   ```bash
   systemctl --user restart opencode.service slack-coordinator.service
   ```

## Troubleshooting

**Service Fails to Start**
- Check logs: `journalctl --user -u opencode.service -n 50`
- Verify credential: `systemd-creds decrypt ~/.config/systemd/user/op_token.cred` (or `op_token` file)
- Verify `op` CLI: `op --version` (must be >= 2.18.0)

**"Permission Denied" on Decryption**
- If using `systemd-creds` with TPM, ensure user has access.
- Fallback: Use the "Protected File" strategy (V4.2 Fallback) if TPM is unavailable (e.g., WSL).

## References
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Systemd Credentials](https://systemd.io/CREDENTIALS/)
