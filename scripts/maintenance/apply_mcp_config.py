import json
import sys
import os

def apply_config(target_path, clean_config_path):
    print(f"Applying clean config to {target_path}...")
    
    if not os.path.exists(target_path):
        print(f"Error: Target file {target_path} not found.")
        sys.exit(1)

    # Backup
    backup_path = target_path + ".bak"
    with open(target_path, 'rb') as src, open(backup_path, 'wb') as dst:
        dst.write(src.read())
    print(f"Backed up to {backup_path}")

    # Read Target
    try:
        with open(target_path, 'r') as f:
            target = json.load(f)
    except json.JSONDecodeError:
        print("Error: Failed to parse target JSON")
        sys.exit(1)

    # Read Clean Config
    try:
        with open(clean_config_path, 'r') as f:
            clean = json.load(f)
    except json.JSONDecodeError:
        print("Error: Failed to parse clean config JSON")
        sys.exit(1)

    # Update mcpServers
    target['mcpServers'] = clean.get('mcpServers', {})
    
    # Save
    with open(target_path, 'w') as f:
        json.dump(target, f, indent=2)
    
    print("Successfully updated mcpServers configuration.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 apply_mcp_config.py <target_file> <clean_config_file>")
        sys.exit(1)
    
    apply_config(sys.argv[1], sys.argv[2])
