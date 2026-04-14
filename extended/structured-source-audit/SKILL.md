---
name: structured-source-audit
description: |
  Audit free, easily ingestible structured public-data sources before adding them
  to product ingestion. Use when evaluating OpenStates, Legistar Web API,
  Socrata, ArcGIS, CKAN, OpenDataSoft, static CSV/XLSX, or deciding whether a
  civic source belongs in the structured-source lane vs scrape/reader lane.
tags: [data, ingestion, public-data, affordabot, architecture, audit]
allowed-tools:
  - Read
  - Bash(rg:*)
  - Bash(git:*)
  - Bash(curl:*)
---

# Structured Source Audit

## Goal

Classify public-data source families into the right ingestion lane before
implementation:

- `structured_lane`: free/public or free-key API/raw-file source, no browser automation.
- `scrape_reader_lane`: useful civic source, but access is portal/page/PDF/search/reader oriented.
- `needs_manual_signup_check`: plausible API exists, but key/free/sample-pull is not verified.
- `reject`: paid-only, blocked, irrelevant, or no usable public records confirmed.

This skill exists to stop agents from treating every civic source as either a
search result or a scraper target. Free structured APIs and raw files should be
ingested through a parallel structured-source path.

## When To Use

Use this skill when the user asks about:

- free structured sources
- API/raw-file civic data
- OpenStates, Legistar Web API, Socrata, ArcGIS, CKAN, OpenDataSoft
- city/county structured data
- whether a source should be searched/scraped or ingested directly
- structured-source POC planning

## Strict Admission Rule

A source can enter `structured_lane` only when the audit records all of:

- signup/key path or `none_required`
- free status
- API/raw-file proof
- sample endpoint/file URL
- no-browser sample pull feasibility
- stable identity fields
- date/update fields
- target jurisdictions or examples
- existing repo refs if already integrated

Sources requiring Playwright, form interaction, rendered portal traversal,
search-first discovery, or brittle HTML scraping belong in `scrape_reader_lane`
even if they expose public PDFs or attachment URLs.

## Audit Matrix

Every audit must return this table shape:

| source_family | signup_or_key_link | free_status | api_or_raw_confirmed | sample_endpoint_or_file_url | sample_pull_without_browser | auth_required | target_examples | record_identity_fields | date_update_fields | existing_repo_refs | recommendation | evidence_links |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

Allowed values:

- `free_status`: `free_public`, `free_key_required`, `free_limited`, `paid_only`, `unknown`
- `api_or_raw_confirmed`: `api`, `bulk_file`, `api_and_bulk`, `raw_public_file`, `raw_official_file`, `not_confirmed`
- `sample_pull_without_browser`: `yes`, `no`, `not_verified`
- `recommendation`: `structured_lane`, `scrape_reader_lane`, `needs_manual_signup_check`, `reject`

## Current Affordabot Baseline

As of the 2026-04-14 affordabot structured-source audit:

`structured_lane` winners:

- OpenStates / Plural Open: free key required; API + bulk data; already partially integrated for California discovery/metadata.
- California LegInfo PUBINFO: no key; official raw ZIP/DAT feeds; best California canonical bulk source.
- LegiScan: free limited API + dataset archives; not integrated.
- Legistar Web API: no key observed; public API; strongest local meetings/local legislation source.
- Socrata / Tyler Data & Insights: public datasets work without auth; app token optional for quota.
- ArcGIS REST / ArcGIS Hub: public items generally require no auth; API and export support.
- CKAN: public datasets generally require no auth; API + resource files.
- OpenDataSoft: public datasets generally require no auth; API + export support.
- Static official CSV/XLSX/TXT/ZIP: no key; direct raw file ingestion.

`scrape_reader_lane` examples:

- Granicus public pages
- city-scrapers
- CivicPlus Agenda Center
- BoardDocs
- NovusAgenda
- PrimeGov
- Swagit
- eScribe
- OpenGov / ClearGov budget books

`needs_manual_signup_check`:

- Accela

`reject` unless exposed through another public structured surface:

- Tyler EnerGov / Enterprise Permitting & Licensing

## POC Selection Rule

Do not POC every candidate source family in the first wave. Pick one source from
each adapter shape:

1. state legislation API/raw feed, e.g. OpenStates or CA PUBINFO
2. local meetings/local legislation API, e.g. Legistar Web API
3. local open-data/GIS table, e.g. Socrata or ArcGIS

This validates the lane boundary and storage/evidence contract. CKAN,
OpenDataSoft, static CSV/XLSX, and LegiScan can follow as catalog/adapter
expansion once the boundary is proven.

## Affordabot Boundary

Windmill should orchestrate refresh schedules, retries, fanout, and freshness.
Affordabot should own source adapters, normalization, canonical identity,
provenance, evidence gates, and economic-analysis dossier construction.

Structured-source refresh should run in parallel to scrape/search/reader refresh:

```text
structured_source_refresh
  -> raw payload artifact
  -> normalized source record
  -> optional official linked document fetch/read
  -> canonical evidence cards
  -> economic research dossier
```

```text
search_or_scrape_reader_refresh
  -> discovered URL
  -> reader/OCR/scraper artifact
  -> normalized source record
  -> canonical evidence cards
  -> economic research dossier
```

## Evidence Hygiene

For internet-derived claims, prefer primary docs:

- official API docs
- official signup/pricing/key pages
- official sample endpoints
- public sample dataset URLs

If free status is not explicit, mark `unknown`; do not infer from successful page
access.
