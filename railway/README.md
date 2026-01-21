# Railway Skills (Official Integration)

Official Railway agent skills, integrated from [railwayapp/railway-skills](https://github.com/railwayapp/railway-skills).

## Overview

Railway has created an official set of agent skills following the Agent Skills open format. This directory contains the synchronized version of those skills, integrated as part of the core agent-skills repository.

## Available Skills

| Skill | Description |
|-------|-------------|
| **status** | Check Railway project status |
| **projects** | List, switch, and configure projects |
| **new** | Create projects, services, databases |
| **service** | Manage existing services |
| **deploy** | Deploy local code |
| **domain** | Manage service domains |
| **environment** | Manage config (vars, commands, replicas) |
| **deployment** | Manage deployments (list, logs, redeploy, remove) |
| **database** | Add Railway databases |
| **templates** | Deploy from marketplace |
| **metrics** | Query resource usage |
| **railway-docs** | Fetch up-to-date Railway documentation |

## Installation

These skills are included in `~/agent-skills/railway/`. If you have agent-skills mounted at `~/.agent/skills`, no additional installation is needed.

### Manual Installation (Alternative)

If you want to install Railway skills directly from the official source:

```bash
# Via Railway installer
curl -fsSL railway.com/skills.sh | bash

# Or via Claude plugin marketplace
claude plugin marketplace add railwayapp/railway-skills
claude plugin install railway@railway-skills
```

## Usage

Each skill has a `SKILL.md` file with detailed instructions. Example for `railway/status`:

```bash
# Check Railway project status
~/.agent/skills/railway/status/SKILL.md
```

## Shared Files

The `_shared/` directory contains common scripts and references used across all Railway skills:

- `scripts/railway-api.sh` - GraphQL API client for Railway
- `references/` - Documentation on Railway concepts

## External Source

Railway skills are maintained by Railway at:
- **Repository**: https://github.com/railwayapp/railway-skills
- **Website**: https://railway.com/skills.sh
- **Author**: Railway
- **License**: MIT

## Synchronization

This directory is synchronized periodically from the official Railway repository to ensure core integration with agent-skills. For the latest updates, see the upstream repository.

## Version History

- **v1.0.0** (2025-01-21): Initial integration from railwayapp/railway-skills
  - Synchronized 12 core Railway skills
  - Added shared scripts and references
