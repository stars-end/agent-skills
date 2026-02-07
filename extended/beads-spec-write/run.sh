#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: run.sh <beads-id>"
  echo "Example: run.sh bd-umrk"
  exit 1
fi

ISSUE_ID=$1

# Ensure BEADS_DIR is set
if [ -z "$BEADS_DIR" ]; then
  export BEADS_DIR="$HOME/bd/.beads"
fi

echo "Checking issue $ISSUE_ID..."

# Get issue type (JSON is an array)
ISSUE_TYPE=$(bd show "$ISSUE_ID" --json 2>/dev/null | jq -r '.[0].issue_type // ""')

if [ -z "$ISSUE_TYPE" ] || [ "$ISSUE_TYPE" = "null" ]; then
  echo "❌ Error: Could not determine issue type for $ISSUE_ID"
  exit 1
fi

echo "✓ Issue $ISSUE_ID is a $ISSUE_TYPE"

# Get current description (JSON is an array) - unescape newlines
CURRENT_DESC=$(bd show "$ISSUE_ID" --json 2>/dev/null | jq -r '.[0].description // ""' | sed 's/\\n/\n/g')

# Function to check if heading exists
heading_exists() {
  local heading="$1"
  echo "$CURRENT_DESC" | grep -q "^${heading}"
}

# Function to append template
append_template() {
  local template="$1"
  CURRENT_DESC="$CURRENT_DESC"$'\n\n'"$template"
}

# Determine required headings and templates based on type
REQUIRED_HEADINGS=""
REQUIRED_TEMPLATES=""

case "$ISSUE_TYPE" in
  epic)
    if heading_exists "## Success Criteria"; then
      echo "✓ Required heading: ## Success Criteria exists"
    else
      echo "✓ Missing required heading: ## Success Criteria"
      echo "✓ Appending template for Success Criteria"
      append_template "## Success Criteria

- [ ] Criterion 1
- [ ] Criterion 2"
      REQUIRED_HEADINGS="yes"
    fi
    ;;
  feature|task)
    if heading_exists "## Acceptance Criteria"; then
      echo "✓ Required heading: ## Acceptance Criteria exists"
    else
      echo "✓ Missing required heading: ## Acceptance Criteria"
      echo "✓ Appending template for Acceptance Criteria"
      append_template "## Acceptance Criteria

- [ ] AC 1: <description>
- [ ] AC 2: <description>"
      REQUIRED_HEADINGS="yes"
    fi
    ;;
  bug)
    BUG_MISSING=""
    if heading_exists "## Steps to Reproduce"; then
      echo "✓ Required heading: ## Steps to Reproduce exists"
    else
      echo "✓ Missing required heading: ## Steps to Reproduce"
      echo "✓ Appending template for Steps to Reproduce"
      append_template "## Steps to Reproduce

1. Step 1
2. Step 2
3. Step 3"
      BUG_MISSING="yes"
      REQUIRED_HEADINGS="yes"
    fi
    
    if heading_exists "## Acceptance Criteria"; then
      echo "✓ Required heading: ## Acceptance Criteria exists"
    else
      echo "✓ Missing required heading: ## Acceptance Criteria"
      echo "✓ Appending template for Acceptance Criteria"
      append_template "## Acceptance Criteria

- [ ] The bug is fixed and no longer occurs
- [ ] No regressions introduced"
      REQUIRED_HEADINGS="yes"
    fi
    ;;
  *)
    echo "⚠️  Warning: Unknown issue type '$ISSUE_TYPE' - no required headings to add"
    ;;
esac

# Add recommended Verification section if missing (optional for lint, but recommended)
if heading_exists "## Verification"; then
  echo "✓ Recommended heading: ## Verification exists"
else
  echo "✓ Checking for recommended heading: ## Verification"
  echo "✓ Appending template for Verification"
  append_template "## Verification

What was run to verify this work:
- [ ] Test X passed
- [ ] Test Y passed
- [ ] Manual verification of Z

Evidence:
- <link to logs/screenshots or paste output>"
fi

# Update issue if changes were made
if [ -n "$REQUIRED_HEADINGS" ]; then
  echo "✓ Updating issue $ISSUE_ID"
  bd update "$ISSUE_ID" --description "$CURRENT_DESC"
else
  echo "✓ No required headings missing (only added optional Verification template)"
  # Still update to add the Verification template
  bd update "$ISSUE_ID" --description "$CURRENT_DESC"
fi

# Run lint to verify
echo ""
echo "Running bd lint..."
if bd lint "$ISSUE_ID" > /dev/null 2>&1; then
  echo "✓ PASS: $ISSUE_ID"
  exit 0
else
  echo "❌ FAIL: $ISSUE_ID"
  bd lint "$ISSUE_ID"
  exit 1
fi
