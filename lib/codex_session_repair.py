from __future__ import annotations

import argparse
import json
import re
import shutil
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


DATA_IMAGE_RE = re.compile(r"data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=\s]+")


@dataclass
class RepairConfig:
    root: Path
    backup_root: Path
    repair: bool = False
    recent_hours: int = 12
    candidate_size_bytes: int = 100 * 1024 * 1024
    line_risk_bytes: int = 1_000_000
    targeted_parse_bytes: int = 200_000
    collapse_string_bytes: int = 500_000
    backup_retention_days: int = 30
    report_path: Path | None = None
    only_paths: list[Path] = field(default_factory=list)


@dataclass
class ScanStats:
    size_bytes: int
    line_count: int
    data_image_lines: int
    image_url_lines: int
    big_lines_gt_threshold: int
    max_line_len: int
    max_line_no: int


@dataclass
class FileResult:
    path: str
    candidate: bool
    skipped_reason: str | None
    before: ScanStats
    after: ScanStats | None = None
    changed_lines: int = 0
    image_items_replaced: int = 0
    data_image_subs: int = 0
    big_strings_collapsed: int = 0
    backup_path: str | None = None


@dataclass
class RunResult:
    host: str
    root: str
    backup_root: str
    repair: bool
    scanned_files: int
    candidate_files: int
    repaired_files: int
    skipped_files: int
    results: list[FileResult]


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%d-%H%M%S")


def count_image_urls(raw: str) -> int:
    return raw.count('"image_url"')


def scan_file(path: Path, line_risk_bytes: int) -> ScanStats:
    size = path.stat().st_size
    line_count = 0
    data_image_lines = 0
    image_url_lines = 0
    big_lines = 0
    max_line_len = 0
    max_line_no = 0
    with path.open("r", errors="ignore") as handle:
        for idx, line in enumerate(handle, start=1):
            line_count += 1
            line_len = len(line)
            if line_len > max_line_len:
                max_line_len = line_len
                max_line_no = idx
            if line_len > line_risk_bytes:
                big_lines += 1
            if "data:image" in line:
                data_image_lines += 1
            if '"image_url"' in line:
                image_url_lines += 1
    return ScanStats(
        size_bytes=size,
        line_count=line_count,
        data_image_lines=data_image_lines,
        image_url_lines=image_url_lines,
        big_lines_gt_threshold=big_lines,
        max_line_len=max_line_len,
        max_line_no=max_line_no,
    )


def is_candidate(stats: ScanStats, cfg: RepairConfig) -> bool:
    return (
        stats.data_image_lines > 0
        or stats.image_url_lines > 0
        or stats.big_lines_gt_threshold > 0
        or stats.size_bytes > cfg.candidate_size_bytes
    )


def should_skip_recent(path: Path, recent_hours: int) -> bool:
    if recent_hours <= 0:
        return False
    cutoff = utc_now() - timedelta(hours=recent_hours)
    modified = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    return modified >= cutoff


def placeholder_text(path: str, *, image: bool = False, original_length: int | None = None) -> str:
    if image:
        return f"[image omitted during Codex recovery at {path}]"
    return (
        f"[omitted oversized text payload during Codex recovery at {path}; "
        f"original length={original_length}]"
    )


def sanitize_value(
    value: Any,
    path: str,
    collapse_string_bytes: int,
    counts: dict[str, int],
) -> Any:
    if isinstance(value, dict):
        if isinstance(value.get("image_url"), str):
            counts["image_items_replaced"] += 1
            return {"type": "input_text", "text": placeholder_text(path, image=True)}
        return {
            key: sanitize_value(
                child,
                f"{path}.{key}" if path else key,
                collapse_string_bytes,
                counts,
            )
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [
            sanitize_value(
                child,
                f"{path}[{idx}]",
                collapse_string_bytes,
                counts,
            )
            for idx, child in enumerate(value)
        ]
    if isinstance(value, str):
        replaced, subs = DATA_IMAGE_RE.subn("[omitted image payload during Codex recovery]", value)
        counts["data_image_subs"] += subs
        if len(replaced) > collapse_string_bytes:
            counts["big_strings_collapsed"] += 1
            return placeholder_text(path, original_length=len(value))
        return replaced
    return value


def backup_destination(backup_root: Path, root: Path, path: Path, stamp: str) -> Path:
    relative_parent = path.relative_to(root).parent
    stamped_root = backup_root / stamp[:8] / relative_parent
    stamped_root.mkdir(parents=True, exist_ok=True)
    return stamped_root / f"{path.name}.bak-{stamp}"


def prune_backups(backup_root: Path, retention_days: int) -> None:
    if retention_days <= 0 or not backup_root.exists():
        return
    cutoff = utc_now() - timedelta(days=retention_days)
    for path in backup_root.rglob("*"):
        if not path.is_file():
            continue
        modified = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
        if modified < cutoff:
            path.unlink(missing_ok=True)


def repair_file(path: Path, cfg: RepairConfig, stamp: str) -> FileResult:
    before = scan_file(path, cfg.line_risk_bytes)
    result = FileResult(
        path=str(path),
        candidate=is_candidate(before, cfg),
        skipped_reason=None,
        before=before,
    )
    if not result.candidate:
        return result
    if should_skip_recent(path, cfg.recent_hours):
        result.skipped_reason = f"recent<{cfg.recent_hours}h"
        return result
    if not cfg.repair:
        result.skipped_reason = "dry_run"
        return result

    backup_path = backup_destination(cfg.backup_root, cfg.root, path, stamp)
    shutil.copy2(path, backup_path)
    tmp_path = path.with_name(path.name + ".repair-tmp")

    changed_lines = 0
    counts = {
        "image_items_replaced": 0,
        "data_image_subs": 0,
        "big_strings_collapsed": 0,
    }

    with path.open("r", errors="ignore") as src, tmp_path.open("w") as dst:
        for raw in src:
            out = raw
            if (
                len(raw) > cfg.targeted_parse_bytes
                or "data:image" in raw
                or '"image_url"' in raw
            ):
                try:
                    payload = json.loads(raw)
                    cleaned = sanitize_value(payload, "", cfg.collapse_string_bytes, counts)
                    out = json.dumps(cleaned, ensure_ascii=False, separators=(",", ":")) + "\n"
                except Exception:
                    out = DATA_IMAGE_RE.sub("[omitted image payload during Codex recovery]", raw)
                    if len(out) > cfg.collapse_string_bytes:
                        out = (
                            '{"timestamp":"recovery","type":"event_msg","payload":'
                            '{"type":"recovered_oversized_line","note":'
                            '"Original oversized line omitted during Codex recovery"}}\n'
                        )
            if out != raw:
                changed_lines += 1
            dst.write(out)

    tmp_path.replace(path)
    result.after = scan_file(path, cfg.line_risk_bytes)
    result.changed_lines = changed_lines
    result.image_items_replaced = counts["image_items_replaced"]
    result.data_image_subs = counts["data_image_subs"]
    result.big_strings_collapsed = counts["big_strings_collapsed"]
    result.backup_path = str(backup_path)
    return result


def collect_paths(cfg: RepairConfig) -> list[Path]:
    if cfg.only_paths:
        return [path.expanduser().resolve() for path in cfg.only_paths if path.exists()]
    return sorted(cfg.root.rglob("rollout-*.jsonl"))


def run(cfg: RepairConfig) -> RunResult:
    stamp = iso_utc(utc_now())
    cfg.backup_root.mkdir(parents=True, exist_ok=True)
    results: list[FileResult] = []
    paths = collect_paths(cfg)
    for path in paths:
        results.append(repair_file(path, cfg, stamp))
    prune_backups(cfg.backup_root, cfg.backup_retention_days)

    run_result = RunResult(
        host=Path.home().name,
        root=str(cfg.root),
        backup_root=str(cfg.backup_root),
        repair=cfg.repair,
        scanned_files=len(paths),
        candidate_files=sum(1 for item in results if item.candidate),
        repaired_files=sum(1 for item in results if item.changed_lines > 0),
        skipped_files=sum(1 for item in results if item.skipped_reason is not None),
        results=results,
    )
    if cfg.report_path is not None:
        cfg.report_path.parent.mkdir(parents=True, exist_ok=True)
        cfg.report_path.write_text(json.dumps(serialize_run_result(run_result), indent=2) + "\n")
    return run_result


def serialize_scan_stats(stats: ScanStats) -> dict[str, Any]:
    payload = asdict(stats)
    payload["size_mb"] = round(stats.size_bytes / 1024 / 1024, 2)
    return payload


def serialize_file_result(result: FileResult) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "path": result.path,
        "candidate": result.candidate,
        "skipped_reason": result.skipped_reason,
        "before": serialize_scan_stats(result.before),
        "after": serialize_scan_stats(result.after) if result.after else None,
        "changed_lines": result.changed_lines,
        "image_items_replaced": result.image_items_replaced,
        "data_image_subs": result.data_image_subs,
        "big_strings_collapsed": result.big_strings_collapsed,
        "backup_path": result.backup_path,
    }
    return payload


def serialize_run_result(result: RunResult) -> dict[str, Any]:
    return {
        "host": result.host,
        "root": result.root,
        "backup_root": result.backup_root,
        "repair": result.repair,
        "scanned_files": result.scanned_files,
        "candidate_files": result.candidate_files,
        "repaired_files": result.repaired_files,
        "skipped_files": result.skipped_files,
        "results": [serialize_file_result(item) for item in result.results],
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backup-first Codex session repair tool")
    parser.add_argument("--root", default="~/.codex/sessions")
    parser.add_argument("--backup-root", default="~/.codex/session-repair-backups")
    parser.add_argument("--repair", action="store_true", help="Apply repairs in place")
    parser.add_argument("--dry-run", action="store_true", help="Scan only")
    parser.add_argument("--recent-hours", type=int, default=12)
    parser.add_argument("--candidate-size-bytes", type=int, default=100 * 1024 * 1024)
    parser.add_argument("--line-risk-bytes", type=int, default=1_000_000)
    parser.add_argument("--targeted-parse-bytes", type=int, default=200_000)
    parser.add_argument("--collapse-string-bytes", type=int, default=500_000)
    parser.add_argument("--backup-retention-days", type=int, default=30)
    parser.add_argument("--report-path")
    parser.add_argument("--path", action="append", default=[], help="Limit scan/repair to one or more session files")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    return parser.parse_args(argv)


def build_config(args: argparse.Namespace) -> RepairConfig:
    repair = args.repair and not args.dry_run
    return RepairConfig(
        root=Path(args.root).expanduser().resolve(),
        backup_root=Path(args.backup_root).expanduser().resolve(),
        repair=repair,
        recent_hours=args.recent_hours,
        candidate_size_bytes=args.candidate_size_bytes,
        line_risk_bytes=args.line_risk_bytes,
        targeted_parse_bytes=args.targeted_parse_bytes,
        collapse_string_bytes=args.collapse_string_bytes,
        backup_retention_days=args.backup_retention_days,
        report_path=Path(args.report_path).expanduser().resolve() if args.report_path else None,
        only_paths=[Path(item) for item in args.path],
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = build_config(args)
    result = run(cfg)
    payload = serialize_run_result(result)
    if args.json:
        print(json.dumps(payload, ensure_ascii=True))
    else:
        print(
            f"scanned={result.scanned_files} candidates={result.candidate_files} "
            f"repaired={result.repaired_files} skipped={result.skipped_files} repair={result.repair}"
        )
        for item in result.results:
            if item.candidate:
                print(
                    f"{item.path} changed={item.changed_lines} skipped={item.skipped_reason or '-'} "
                    f"before_max={item.before.max_line_len} "
                    f"after_max={(item.after.max_line_len if item.after else '-')}"
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
