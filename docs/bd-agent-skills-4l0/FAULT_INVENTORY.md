# Fault Inventory

Known bugs from the Hive Queen incident and current gaps.

---

## 🔴 Critical (Machine Crash Risk)

| ID | File | Bug | Impact | Fix |
|----|------|-----|--------|-----|
| C1 | hive-queen.py:122-126 | No concurrency limit | Unlimited agents spawn | Add MAX_CONCURRENT_AGENTS=2 |
| C2 | hive-queen.py:103 | Status updated AFTER dispatch | Race allows duplicates | Update BEFORE dispatch |
| C3 | hive-queen.py:121 | No in-memory deduplication | Multiple spawns per session | dispatched_tasks Set |
| C4 | dispatch.py:42-48 | No resource limits | Single agent consumes all | systemd-run limits |

---

## 🟠 High (Correctness/Security)

| ID | File | Bug | Impact | Fix |
|----|------|-----|--------|-----|
| H1 | dispatch.py:24 | Hardcoded API token | Security vulnerability | Use env passthrough |
| H2 | hive-queen.service:10 | Restart=always no limit | Crash loop spawns Pythons | Add StartLimitBurst=3 |
| H3 | hive-queen.py:30-46 | Direct JSONL read w/o lock | Race with bd CLI | Use bd CLI instead |
| H4 | cleanup.sh:29 | 2-hour stale threshold | Pods accumulate | Reduce to 30 min |

---

## 🟡 Medium (Operational)

| ID | File | Bug | Impact | Fix |
|----|------|-----|--------|-----|
| M1 | hive-status.py | No CPU/RAM metrics | No visibility | Add psutil |
| M2 | hive-queen.py:106-115 | sync_repo() fails silently | Tasks not picked up | Add error handling |
| M3 | create.sh:29-34 | Auto-clone on missing repo | Unexpected repos | Fail if not exists |
| M4 | enable-queen.sh | No pre-flight checks | Starts broken service | Add dx-check first |

---

## Fix: Concurrency + Deduplication

```python
MAX_CONCURRENT_AGENTS = 2
dispatched_this_session = set()

def dispatch_bead(bead):
    task_id = bead['id']
    
    # Deduplication
    if task_id in dispatched_this_session:
        return
    
    # Concurrency
    if get_active_agent_count() >= MAX_CONCURRENT_AGENTS:
        return
    
    # CRITICAL: Mark BEFORE dispatch
    dispatched_this_session.add(task_id)
    subprocess.run(["bd", "update", task_id, "--status", "in_progress"])
    
    # Then dispatch...
```

---

## Fix: Resource Limits

```python
agent_cmd = [
    "systemd-run", "--user",
    f"--unit={unit_name}",
    "-p", "CPUQuota=50%",
    "-p", "MemoryMax=4G",
    "-p", "TasksMax=50",
    "--",
    "script", "-q", "-e", "-c", cmd, log_path
]
```

---

## Root Cause: Why 10-20 Agents Spawned

```
T=0s:   Queen reads JSONL, finds 3 tasks (status=open)
T=1s:   Dispatch agent-1 for task-A
T=2s:   Dispatch agent-2 for task-B  
T=3s:   Dispatch agent-3 for task-C
T=4s:   bd update task-A --status in_progress (async)
...
T=30s:  Queen reads JSONL again (may not have all updates!)
T=31s:  Dispatch agent-4 for task-A (DUPLICATE!)
```

**Core Issue:** No atomic feedback loop, no deduplication.
