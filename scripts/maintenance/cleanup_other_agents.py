import sys
import os
import json

def cleanup_gemini(path):
    if not os.path.exists(path): 
        # Don't print error, just skip silently or info?
        # print(f"Gemini config not found at {path}")
        return
    
    print(f"Cleaning Gemini config: {path}")
    try:
        with open(path, 'r') as f:
            data = json.load(f)
        
        changed = False
        
        roots = ['mcp', 'mcpServers']
        targets = ['skills', 'universal-skills', 'universal_skills', 'mcp-agent-mail', 'agent-mail', 'mcp_agent_mail']
        
        for root in roots:
            if root in data:
                for target in targets:
                    if target in data[root]:
                        del data[root][target]
                        print(f"Removed '{target}' from '{root}'")
                        changed = True
        
        if changed:
            with open(path + ".bak", 'w') as f:
                json.dump(data, f, indent=2)
            
            with open(path, 'w') as f:
                json.dump(data, f, indent=2)
            print("Gemini config updated.")
        else:
            print("Gemini config already clean.")
    except Exception as e:
        print(f"Error processing Gemini config: {e}")

def cleanup_codex(path):
    if not os.path.exists(path):
        return
        
    print(f"Cleaning Codex config: {path}")
    try:
        with open(path, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        skip = False
        found = False
        
        targets = [
            '[mcp_servers.skills]', '[mcp_servers."skills"]',
            '[mcp_servers.universal-skills]', '[mcp_servers."universal-skills"]',
            '[mcp_servers.universal_skills]', '[mcp_servers."universal_skills"]',
            '[mcp_servers.agent-mail]', '[mcp_servers."agent-mail"]',
            '[mcp_servers.mcp-agent-mail]', '[mcp_servers."mcp-agent-mail"]',
            '[mcp_servers.mcp_agent_mail]', '[mcp_servers."mcp_agent_mail"]'
        ]

        for line in lines:
            stripped = line.strip()
            is_target_start = False
            for t in targets:
                if stripped.startswith(t):
                    is_target_start = True
                    break
            
            if is_target_start:
                skip = True
                found = True
            elif skip and stripped.startswith('['):
                is_next_target = False
                for t in targets:
                    if stripped.startswith(t):
                        is_next_target = True
                        break
                
                if is_next_target:
                    skip = True
                else:
                    skip = False
            
            if not skip:
                new_lines.append(line)
        
        if found:
            with open(path + ".bak", 'w') as f:
                f.writelines(lines)
                
            with open(path, 'w') as f:
                f.writelines(new_lines)
            print("Codex config updated.")
        else:
            print("Codex config already clean.")
    except Exception as e:
        print(f"Error processing Codex config: {e}")

if __name__ == "__main__":
    home = os.path.expanduser("~")
    
    gemini_paths = [
        os.path.join(home, ".gemini", "settings.json"),
        os.path.join(home, ".gemini", "antigravity", "mcp_config.json")
    ]
    
    # If args provided, treat as extra or specific overrides?
    # Keeping it simple: scan default paths.
    
    for gp in gemini_paths:
        cleanup_gemini(gp)
    
    codex_path = os.path.join(home, ".codex", "config.toml")
    cleanup_codex(codex_path)
