#!/usr/bin/env python3
"""Nightly z.ai enrichment job for context-plus semantic artifacts.

Reads existing .mcp_data/embeddings-cache.json from each tracked repo,
produces cluster labels, file summaries, and semantic descriptions via z.ai.

Usage:
    python3 scripts/enrichment/nightly-enrichment.py [--dry-run] [--repo /path/to/repo]

Env vars:
    ZAI_API_KEY        - Required. z.ai API key (op://dev/Agent-Secrets-Production/ZAI_API_KEY)
    ZAI_MODEL          - Default: glm-4.7
    OPENROUTER_API_KEY - Not needed (reads existing cache, no live embeddings)
    ENRICHMENT_BATCH   - Files per cluster for labeling. Default: 20
    ENRICHMENT_TIMEOUT - Per-call timeout seconds. Default: 30
    ENRICHMENT_OUTPUT  - Override output dir. Default: .mcp_data/enrichment/

Artifacts (written per repo):
    .mcp_data/enrichment/cluster-labels.json
    .mcp_data/enrichment/file-summaries.json
    .mcp_data/enrichment/semantic-descriptions.json
"""

import argparse
import asyncio
import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

CANONICAL_REPOS = [
    Path.home() / "agent-skills",
    Path.home() / "prime-radiant-ai",
    Path.home() / "affordabot",
    Path.home() / "llm-common",
]

CACHE_FILE = ".mcp_data/embeddings-cache.json"
OUTPUT_DIR = ".mcp_data/enrichment"


@dataclass
class FileEntry:
    path: str
    header: str = ""
    symbols: list[str] = field(default_factory=list)


@dataclass
class ClusterLabel:
    cluster_index: int
    label: str
    theme: str
    files: list[str] = field(default_factory=list)


@dataclass
class FileSummary:
    path: str
    summary: str


@dataclass
class SemanticDescription:
    path: str
    description: str


def load_embedding_cache(repo_root: Path) -> dict:
    """Load embedding cache, handling both V1 and V2 formats."""
    cache_path = repo_root / CACHE_FILE
    if not cache_path.exists():
        return {}
    try:
        raw = json.loads(cache_path.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and raw.get("version") == 2 and "entries" in raw:
            return raw["entries"]
        return raw
    except Exception as e:
        log.warning("Failed to load cache from %s: %s", cache_path, e)
        return {}


def extract_file_entries(cache: dict, repo_root: Path) -> list[FileEntry]:
    """Extract file entries from cache data."""
    entries = []
    for path, data in cache.items():
        if not isinstance(data, dict) or "vector" not in data:
            continue
        full_path = repo_root / path
        if not full_path.exists():
            continue

        header = ""
        symbols: list[str] = []

        try:
            content = full_path.read_text(encoding="utf-8", errors="replace")
            lines = content.split("\n")
            header_lines: list[str] = []
            for line in lines[:5]:
                trimmed = line.strip()
                if trimmed.startswith(("//", "#", "--")):
                    header_lines.append(trimmed.lstrip("/#- ").strip())
                elif trimmed:
                    break
            header = " ".join(header_lines)[:200]

            import re
            symbol_matches = re.findall(r"(?:def |class |function |const |let |var |export )(?:async )?(\w+)", content[:3000])
            symbols = symbol_matches[:5]
        except Exception:
            pass

        entries.append(FileEntry(path=path, header=header, symbols=symbols))

    return entries


def cluster_files(entries: list[FileEntry], batch_size: int) -> list[list[FileEntry]]:
    """Split files into clusters for labeling."""
    if not entries:
        return []
    clusters = []
    for i in range(0, len(entries), batch_size):
        clusters.append(entries[i:i + batch_size])
    return clusters


CLUSTER_LABEL_PROMPT = """You are labeling clusters of code files. For each cluster below, produce EXACTLY
one JSON array of objects, each with:
- "label": 2-3 words describing the cluster
- "theme": a sentence about the cluster's purpose

{clusters}

Respond with ONLY a JSON array. No other text."""

FILE_SUMMARY_PROMPT = """Provide a 5-10 word semantic description of this file for code search indexing.

File: {path}
Header: {header}
Symbols: {symbols}

Respond with ONLY the description text."""


async def call_zai(prompt: str, api_key: str, model: str, timeout: int = 30) -> str:
    """Call z.ai API using raw httpx (no llm-common dependency required)."""
    import httpx

    url = "https://api.z.ai/api/anthropic/v1/messages"
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = {
        "model": model,
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
    }

    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(url, headers=headers, json=payload)
        resp.raise_for_status()
        data = resp.json()
        return data["content"][0]["text"]


async def generate_cluster_labels(
    clusters: list[list[FileEntry]], api_key: str, model: str, timeout: int
) -> list[ClusterLabel]:
    """Generate labels for each cluster via z.ai."""
    labels: list[ClusterLabel] = []
    for i, cluster in enumerate(clusters):
        cluster_desc = "\n".join(
            f"  {e.path}: {e.header or 'no description'}" for e in cluster
        )
        prompt = CLUSTER_LABEL_PROMPT.format(clusters=f"Cluster {i + 1}:\n{cluster_desc}")

        try:
            response = await call_zai(prompt, api_key, model, timeout)
            json_match = __import__("re").search(r"\[[\s\S]*\]", response)
            if json_match:
                parsed = json.loads(json_match.group())
                if parsed and isinstance(parsed, list):
                    item = parsed[0]
                    labels.append(ClusterLabel(
                        cluster_index=i,
                        label=item.get("label", f"Cluster {i + 1}"),
                        theme=item.get("theme", ""),
                        files=[e.path for e in cluster],
                    ))
                    continue
        except Exception as e:
            log.warning("Failed to label cluster %d: %s", i, e)

        labels.append(ClusterLabel(
            cluster_index=i,
            label=f"Cluster {i + 1}",
            theme="",
            files=[e.path for e in cluster],
        ))

    return labels


async def generate_file_summaries(
    entries: list[FileEntry], api_key: str, model: str, timeout: int
) -> list[FileSummary]:
    """Generate summaries for individual files via z.ai."""
    summaries: list[FileSummary] = []
    for entry in entries:
        prompt = FILE_SUMMARY_PROMPT.format(
            path=entry.path,
            header=entry.header or "no description",
            symbols=", ".join(entry.symbols) if entry.symbols else "none",
        )
        try:
            response = await call_zai(prompt, api_key, model, timeout)
            summaries.append(FileSummary(path=entry.path, summary=response.strip()))
        except Exception as e:
            log.warning("Failed to summarize %s: %s", entry.path, e)
            summaries.append(FileSummary(path=entry.path, summary=entry.header or "unknown"))

    return summaries


async def generate_semantic_descriptions(
    entries: list[FileEntry], api_key: str, model: str, timeout: int
) -> list[SemanticDescription]:
    """Generate semantic descriptions for agent prompt enrichment."""
    descriptions: list[SemanticDescription] = []
    for entry in entries:
        prompt = (
            f"Describe this code file in one sentence for an AI agent's context. "
            f"Focus on what it does, not how.\n\n"
            f"File: {entry.path}\n"
            f"Header: {entry.header or 'no description'}\n"
            f"Symbols: {', '.join(entry.symbols) if entry.symbols else 'none'}"
        )
        try:
            response = await call_zai(prompt, api_key, model, timeout)
            descriptions.append(SemanticDescription(path=entry.path, description=response.strip()))
        except Exception as e:
            log.warning("Failed to describe %s: %s", entry.path, e)
            descriptions.append(SemanticDescription(path=entry.path, description=entry.header or ""))

    return descriptions


async def enrich_repo(
    repo_root: Path, api_key: str, model: str, batch_size: int, timeout: int, dry_run: bool
) -> dict:
    """Enrich a single repository."""
    result = {
        "repo": str(repo_root),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "files_found": 0,
        "clusters_labeled": 0,
        "summaries_generated": 0,
        "descriptions_generated": 0,
        "errors": [],
    }

    cache = load_embedding_cache(repo_root)
    if not cache:
        log.info("No embedding cache found in %s, skipping", repo_root)
        return result

    entries = extract_file_entries(cache, repo_root)
    result["files_found"] = len(entries)

    if not entries:
        log.info("No valid file entries in %s cache, skipping", repo_root)
        return result

    log.info("Processing %d files from %s", len(entries), repo_root)

    if dry_run:
        log.info("[DRY RUN] Would generate labels, summaries, descriptions for %d files", len(entries))
        result["clusters_labeled"] = len(cluster_files(entries, batch_size))
        result["summaries_generated"] = len(entries)
        result["descriptions_generated"] = len(entries)
        return result

    clusters = cluster_files(entries, batch_size)
    log.info("Split into %d clusters (batch_size=%d)", len(clusters), batch_size)

    cluster_labels = await generate_cluster_labels(clusters, api_key, model, timeout)
    result["clusters_labeled"] = len(cluster_labels)

    file_summaries = await generate_file_summaries(entries, api_key, model, timeout)
    result["summaries_generated"] = len(file_summaries)

    semantic_descs = await generate_semantic_descriptions(entries, api_key, model, timeout)
    result["descriptions_generated"] = len(semantic_descs)

    output_dir = repo_root / OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / "cluster-labels.json").write_text(
        json.dumps([asdict(c) for c in cluster_labels], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (output_dir / "file-summaries.json").write_text(
        json.dumps([asdict(s) for s in file_summaries], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (output_dir / "semantic-descriptions.json").write_text(
        json.dumps([asdict(d) for d in semantic_descs], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    log.info(
        "Wrote 3 artifacts to %s: %d labels, %d summaries, %d descriptions",
        output_dir, len(cluster_labels), len(file_summaries), len(semantic_descs),
    )

    return result


async def main() -> int:
    parser = argparse.ArgumentParser(description="Nightly z.ai enrichment for context-plus")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without calling z.ai")
    parser.add_argument("--repo", type=Path, action="append", help="Specific repo path (repeatable)")
    parser.add_argument("--batch-size", type=int, default=int(os.environ.get("ENRICHMENT_BATCH", "20")))
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("ENRICHMENT_TIMEOUT", "30")))
    parser.add_argument("--model", default=os.environ.get("ZAI_MODEL", "glm-4.7"))
    parser.add_argument("--api-key", default=os.environ.get("ZAI_API_KEY", ""))
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    if not args.api_key:
        log.error("ZAI_API_KEY is required. Set env var or use --api-key")
        return 1

    repos = args.repo if args.repo else [r for r in CANONICAL_REPOS if r.exists()]
    if not repos:
        log.error("No repos found. Pass --repo or ensure canonical repos exist.")
        return 1

    log.info("Nightly enrichment starting: %d repos, model=%s, batch=%d, dry_run=%s",
             len(repos), args.model, args.batch_size, args.dry_run)

    results = []
    for repo in repos:
        try:
            result = await enrich_repo(
                repo, args.api_key, args.model, args.batch_size, args.timeout, args.dry_run
            )
            results.append(result)
        except Exception as e:
            log.error("Failed to enrich %s: %s", repo, e)
            results.append({"repo": str(repo), "error": str(e)})

    total_files = sum(r.get("files_found", 0) for r in results)
    total_labels = sum(r.get("clusters_labeled", 0) for r in results)
    total_summaries = sum(r.get("summaries_generated", 0) for r in results)
    total_errors = sum(len(r.get("errors", [])) for r in results)

    log.info(
        "Enrichment complete: %d repos, %d files, %d clusters, %d summaries, %d errors",
        len(results), total_files, total_labels, total_summaries, total_errors,
    )

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps({
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "model": args.model,
                "dry_run": args.dry_run,
                "results": results,
                "totals": {
                    "repos": len(results),
                    "files": total_files,
                    "clusters": total_labels,
                    "summaries": total_summaries,
                    "errors": total_errors,
                },
            }, indent=2),
            encoding="utf-8",
        )

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
