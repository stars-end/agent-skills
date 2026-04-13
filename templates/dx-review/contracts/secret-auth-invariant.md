## Secret-Auth Invariant (Review Lane)

Reviewers must not perform routine secret access.

- Forbidden for routine review:
  - direct 1Password CLI secret reads
  - direct 1Password CLI item lookup/listing
  - direct 1Password CLI account/session probes
- Do not attempt OP auth repair loops in review lanes.
- Do not print or request secret values in findings.

If a review appears blocked on credentials, return a finding that names the missing evidence and classify the run as blocked by auth context, rather than attempting secret retrieval.
