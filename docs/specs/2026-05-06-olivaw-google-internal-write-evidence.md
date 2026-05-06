# Olivaw Google Internal-Write Evidence

Feature-Key: `bd-wf9zw`
Date: 2026-05-06
Account: `fengning@stars-end.ai`

## Setup Result

`scripts/olivaw-google-ops-bootstrap.sh` completed successfully after reauthing
the `olivaw-gog` OAuth client with Gmail write scopes.

State file:

```bash
~/.hermes/profiles/olivaw/google-ops-state.env
```

Created or bound artifacts:

| Surface | Artifact | ID |
| --- | --- | --- |
| Drive | `Olivaw Ops` | `1YLn5AtqSI13svSscVKSKN9PV9i1EzUZx` |
| Drive | `00 Inbox Drop` | `1Btu-RUWKIepaAWJLqne41BYOaDTBRTaT` |
| Drive | `01 Drafts For Review` | `1lOS9KNnbJ0dxg0NkH3E88hb7aJUjifnk` |
| Drive | `02 Approved Working Files` | `1FzTq6LH6tj3Jg_xxv9wVBg33K-C1fI6w` |
| Drive | `03 Finance Admin` | `1ddqmxyCKWGg3hzgRLvcCX_Pqp-am5h0u` |
| Drive | `04 Healthcare Admin` | `1cEc-zD_egFlWrI8V8Mshx1D51KYTvId_` |
| Drive | `05 Reservations` | `1uzvCxuKY0V_AfH28HkXHZoHR7F-Ez4iO` |
| Drive | `90 Archive` | `1v7ywBPVMblNJchlMlXkn6Q8MihWdQ4uB` |
| Drive | `99 Audit Logs` | `14D75Y6II7LqSd42XYjNac-JeMoAhGUzE` |
| Sheets | `Olivaw Ops Tracker` | `187R5btO1JC6xmFGmf7hEubFziK7b8iz_TLmGalp-YyI` |
| Calendar | Olivaw business calendar | `fengning@stars-end.ai` |

Gmail labels created:

- `Olivaw/Inbox`
- `Olivaw/Needs Review`
- `Olivaw/Draft Created`
- `Olivaw/Waiting On Fengning`
- `Olivaw/Waiting On External`
- `Olivaw/Done`
- `Olivaw/Finance`
- `Olivaw/Healthcare`
- `Olivaw/Reservations`
- `Olivaw/Startup Ops`

## Final Canary

Command:

```bash
scripts/olivaw-google-ops-canary.sh > /tmp/olivaw-google-canary-final.json
```

Result:

```json
{
  "ok": true,
  "correlation_id": "olivaw-google-canary-20260506T130022Z",
  "created": {
    "drive_upload_id": "1RWkzk3VUBjtGVfdXcsjp6jBlrvyOG-kA",
    "doc_id": "1MFWN7my0cdCrm1Vl0dePDUOHLMzGobwYbZmUDLng598",
    "gmail_draft_id": "r-6698888109896921722",
    "calendar_event_id": "1h20tanc2fjti5mcn5hj8agqvs"
  }
}
```

Blocked-action tests passed:

- Gmail send blocked.
- Gmail draft send blocked.
- Drive share blocked.
- Drive delete blocked.
- Drive upload outside approved folder blocked.
- Docs create outside approved folder blocked.
- Sheets append against non-tracker spreadsheet blocked.
- Calendar attendees blocked.
- Calendar non-Olivaw summary blocked.
- Calendar delete blocked.

## Manual Verification

Computer Use / Chrome checks:

- Drive opened `Olivaw Ops` under `fengning@stars-end.ai`; all approved folders
  were visible.
- Sheets opened `Olivaw Ops Tracker`; all required tabs were visible:
  `Intake`, `Approvals`, `Artifacts`, `Reservations`, `Finance Admin`,
  `Healthcare Admin`, `Calendar Holds`, `Audit`.
- Gmail search found the synthetic draft:
  `[Olivaw Draft] Synthetic draft canary 20260506T130022Z`.
- Gmail sidebar showed the `Olivaw/*` labels.
- Calendar opened the business account calendar for the canary event; CLI event
  inspection verified no attendees and `extendedProperties.private.olivaw_managed=true`.

## Notes

- A temporary synthetic folder named `__olivaw_scope_probe_drive_direct__` exists
  under `Olivaw Ops` from an early direct API probe. It was not deleted because
  Drive delete is intentionally blocked by the approved runtime policy.
- No live finance, healthcare, reservation, banking, or external recipient
  payloads were used. All canary payloads were synthetic.

