# Research Memo: OSS Search Alternatives for Affordabot Discovery

#$1

## Candidate Systems

| System | Primary Function | Linux Viability | Operational Complexity |
| :--- | :--- | :--- | :--- |
| **CDP (Council Data Project)** | Automated Transcripts/NLP | High (Serverless) | Low |
| **Councilmatic** | Legislation Tracking | High (Django) | High (Scrapers) |
| **Aleph** | Deep Document Search | High (Docker) | High (DB-heavy) |
| **Typesense** | Search Indexing | High (Binary) | Low |

## Recommended Benchmark Wave

We should NOT rely on generic metasearch to solve discovery. We need to shift to "official-root-first" discovery.

### Proposed Benchmark Matrix

| Candidate | Integration Tier | Benchmark Task |
| :--- | :--- | :--- |
| **Typesense** | Storage Layer | Index existing scrapes; verify search speed/relevancy. |
| **CDP** | Discovery Layer | Evaluate pipeline for automated transcript ingestion. |
| **Aleph** | Deep Retrieval | Ingest 100 PDFs; query entity extraction/cross-referencing. |

## Verdict:
- **Immediate:** Benchmark **Typesense** for the existing scraped corpus to replace Z.ai.
- **Strategic:** Invest in **CDP (Council Data Project)** for modern, low-maintenance, NLP-enhanced discovery rather than traditional scraping-heavy Councilmatic.
- **Fallback:** Use **Aleph** only when we need structured analysis of large document collections that cannot be easily scraped.

---
PR_URL: none
PR_HEAD_SHA: none$3
PR_URL: none
PR_HEAD_SHA: none
