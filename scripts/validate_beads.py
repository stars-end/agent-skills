import os
import sys
import json

if os.getenv("BEADS_JSONL_COMPAT", "0") != "1":
    print("✅ Beads JSONL integrity checks skipped (compatibility mode off).")
    print("Set BEADS_JSONL_COMPAT=1 to run legacy JSONL validation.")
    sys.exit(0)

def validate_jsonl(file_path):
    """
    Validates that a .jsonl file has valid JSON on every line.
    """
    if not os.path.exists(file_path):
        return True 

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    errors = []
    for i, line in enumerate(lines):
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
        except json.JSONDecodeError:
            if line.startswith('<<<<<<<') or line.startswith('======='):
                errors.append(f"Line {i+1}: Git conflict marker detected")
            else:
                errors.append(f"Line {i+1}: Invalid JSON")

    if errors:
        print(f"❌ Beads Integrity Check Failed for {file_path}")
        for err in errors:
            print(f"   - {err}")
        return False
    
    return True

if __name__ == "__main__":
    files_to_check = [".beads/issues.jsonl", ".beads/deletions.jsonl"]
    success = True
    for fp in files_to_check:
        if not validate_jsonl(fp):
            success = False

    if not success:
        print("\n💥 COMMIT BLOCKED: Beads database is corrupt.")
        print("   Please fix the JSONL file manually before committing.")
        sys.exit(1)
        
    print("✅ Beads integrity verified.")
    sys.exit(0)
