# Secrets Management

## 1Password (Primary)

```bash
# Read secret
op read op://dev/Agent-Secrets-Production/ZAI_API_KEY

# List available secrets
op items list --vault dev

# Quick reference skill
# Use: op-secrets-quickref
```

## Railway (Runtime)

```bash
# Connect to Railway shell (provides all env vars)
railway shell

# Variables available:
# - RAILWAY_SERVICE_FRONTEND_URL
# - RAILWAY_SERVICE_BACKEND_URL
# - All project secrets
```

## Environment Files

- Never commit `.env` files
- Use `op inject` for local development
- Railway vars only for app runtime

## See Also
- `core/op-secrets-quickref/SKILL.md` - Full 1Password guide
- `docs/SECRET_MANAGEMENT.md` - Architecture details
- `docs/ENV_SOURCES_CONTRACT.md` - Env source contract
