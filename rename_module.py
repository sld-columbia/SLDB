#!/usr/bin/env python3

import sys
import re
from pathlib import Path

def rename_verilog_module(file_path: str, old_name: str, new_name: str):
    path = Path(file_path)
    if not path.exists():
        print(f"[ERROR] File not found: {file_path}")
        return

    with open(path, "r") as f:
        lines = f.readlines()

    changed = False
    new_lines = []

    module_decl_re = re.compile(rf"^\s*module\s+{re.escape(old_name)}\b")
    endmodule_comment_re = re.compile(rf"^\s*endmodule\s*//\s*{re.escape(old_name)}\s*$")

    for line in lines:
        if module_decl_re.match(line):
            line = line.replace(f"module {old_name}", f"module {new_name}")
            changed = True
        elif endmodule_comment_re.match(line):
            line = f"endmodule // {new_name}\n"
            changed = True
        new_lines.append(line)

    if not changed:
        print(f"[WARN] No module named '{old_name}' found in {file_path}")
        return

    # Backup original
    backup_path = path.with_suffix(path.suffix + ".bak")
    path.rename(backup_path)

    # Write new file
    with open(path, "w") as f:
        f.writelines(new_lines)

    print(f"[OK] Renamed module '{old_name}' → '{new_name}' in {file_path}")
    print(f"[INFO] Original saved as {backup_path}")

# ---------------------------------------------------------------------------
# Usage: python rename_module.py <file.v> <old_module_name> <new_module_name>
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python rename_module.py <file.v> <old_module_name> <new_module_name>")
        sys.exit(1)

    file_v = sys.argv[1]
    old = sys.argv[2]
    new = sys.argv[3]

    rename_verilog_module(file_v, old, new)
