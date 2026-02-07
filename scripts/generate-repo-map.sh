#!/bin/bash
# scripts/generate-repo-map.sh
# Generate REPO_MAP.md for a product repo
# Usage: ./generate-repo-map.sh [repo-path]

set -euo pipefail

REPO="${1:-.}"
OUT="$REPO/REPO_MAP.md"

cat > "$OUT" <<INNER_EOF
# Repo Structure Map
<!-- Generated: \$(date -u +%Y-%m-%dT%H:%M:%SZ) -->
<!-- Regenerate: make map -->

## File Tree (depth 2)
```
\$(cd "\$REPO" && tree -L 2 -I 'node_modules|__pycache__|.git|.next|dist|build|.venv|venv' 2>/dev/null | head -60 || find . -maxdepth 2 -type d | grep -v node_modules | grep -v __pycache__ | grep -v .git | head -40)
```

## API Routes
```
\$(grep -rh "@app\.\(get\|post\|put\|delete\|patch\)\|@router\.\(get\|post\|put\|delete\|patch\)" "\$REPO"/backend/ "\$REPO"/api/ "\$REPO"/src/api/ 2>/dev/null | head -25 || echo "No routes found")
```

## Database Tables
```
\$(grep -h "CREATE TABLE" "\$REPO"/supabase/migrations/*.sql "\$REPO"/migrations/*.sql "\$REPO"/db/*.sql 2>/dev/null | sed 's/CREATE TABLE //' | head -15 || echo "No migrations found")
```
INNER_EOF

LINES=\$(wc -l < "\$OUT" | tr -d ' ')
echo "✅ Generated: \$OUT (\$LINES lines)"
