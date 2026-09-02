#!/usr/bin/env python3

import os
import sys
import re

def validate_skill(skill_dir):
    print(f"Validating skill at: {skill_dir}")
    
    if not os.path.isdir(skill_dir):
        print(f"FAIL: Directory '{skill_dir}' does not exist.")
        return False
        
    skill_md_path = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md_path):
        print(f"FAIL: SKILL.md not found in '{skill_dir}'.")
        return False
        
    try:
        with open(skill_md_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"FAIL: Could not read SKILL.md: {e}")
        return False
        
    # Extract YAML frontmatter
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
    if not match:
        print("FAIL: SKILL.md is missing valid YAML frontmatter surrounded by '---'.")
        return False
        
    frontmatter = match.group(1)
    metadata = {}
    
    for line in frontmatter.split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            metadata[key.strip()] = val.strip().strip("'\"")
            
    # Check name
    name = metadata.get('name')
    if not name:
        print("FAIL: 'name' is required in frontmatter.")
        return False
        
    if not re.match(r'^[a-z0-9\-]+$', name):
        print(f"FAIL: 'name' ('{name}') must be kebab-case (lowercase, digits, hyphens only).")
        return False
        
    if len(name) > 64:
        print(f"FAIL: 'name' must be <= 64 characters (current: {len(name)}).")
        return False
        
    # Check description
    description = metadata.get('description')
    if not description:
        print("FAIL: 'description' is required in frontmatter.")
        return False
        
    if len(description) > 1024:
        print(f"FAIL: 'description' must be <= 1024 characters (current: {len(description)}).")
        return False
        
    if '<' in description or '>' in description:
        print("FAIL: 'description' cannot contain angle brackets ('<' or '>').")
        return False

    print("PASS: Frontmatter validation successful.")
    
    # Check directories
    allowed_dirs = {'scripts', 'references', 'assets', 'evals'}
    actual_dirs = [d for d in os.listdir(skill_dir) if os.path.isdir(os.path.join(skill_dir, d)) and not d.startswith('.')]
    
    for d in actual_dirs:
        if d not in allowed_dirs:
            print(f"WARNING: Unrecognized directory '{d}' found. Standard directories are: scripts/, references/, assets/.")
            
    print("PASS: Directory structure validation successful.")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <path_to_skill_directory>")
        sys.exit(1)
        
    target_dir = sys.argv[1]
    success = validate_skill(target_dir)
    
    if success:
        print("\nOVERALL STATUS: PASS")
        sys.exit(0)
    else:
        print("\nOVERALL STATUS: FAIL")
        sys.exit(1)
