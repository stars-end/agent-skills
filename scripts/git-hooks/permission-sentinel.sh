#!/bin/bash
# Only target scripts/ and bin/ directories to avoid python module pollution
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E "^(scripts|bin)/.*\.(sh|py)$")
if [ -n "$FILES" ]; then
    for file in $FILES; do
        # Only chmod if shebang exists
        if head -n 1 "$file" | grep -q "^#!" 2>/dev/null; then
            chmod +x "$file"
            # Only re-add the specific file
            git add "$file"
        fi
    done
fi
exit 0
