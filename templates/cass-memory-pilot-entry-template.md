# CASS Memory Pilot Entry Template

Use this template for sanitized, reusable procedural entries.

## Metadata

- Title:
- Date (UTC):
- Author:
- Status: candidate
- Category:
- Confidence: low | medium | high
- Incident Class: DX/control-plane
- Scope:
- Host(s):
- Runtime/Client:
- Related Beads ID:

## Trigger Pattern

Describe the symptom pattern that should trigger this playbook.

## Preconditions

List assumptions and prerequisites.

## Validated Procedure

1. 
2. 
3. 

## Failure / Rollback Signal

What indicates this procedure is not working and should be stopped?

## Reuse Guidance

When should this be reused, and when should it not?

## Promotion Gate

What must happen before this candidate becomes durable shared memory?

- Reused successfully in 2+ incidents, or
- Explicitly validated by operator, or
- Backed by stable runbook/contract plus one successful reuse

## Prune Conditions

When should this candidate be dropped or marked obsolete?

- superseded
- harmful/misleading
- too repo-specific
- duplicates an existing runbook or established memory

## Redaction Check

Confirm the entry contains none of:
- secrets/tokens
- session identifiers/cookies
- full raw logs with sensitive payloads
- full user transcripts

## Source References

- PR URL:
- File path(s):
- Runbook/doc link(s):
- Runtime evidence / command notes:

## One-Paragraph Summary For `cm playbook add`

Write a compact summary suitable for storage in cass-memory:

> 
