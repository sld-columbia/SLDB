
#!/usr/bin/env python3
"""
Move a curated list of RTL files from a *large* RTL dump (many repos)
into per-accelerator folders.

*   Each accelerator gets its own destination folder.
*   You may provide an optional *path hint* (relative to BASE_RTL_ROOT)
    to limit the search – useful when a repo contains more than one accel.

Replace `BASE_RTL_ROOT` with the directory that contains **all** repos
you previously extracted from the RTL-Repo dataset.
"""

import os
import shutil
from pathlib import Path
from typing import List, Optional

# ---------------------------------------------------------------------------
# 1)  WHERE YOUR FULL RTL TREE LIVES
# ---------------------------------------------------------------------------
BASE_RTL_ROOT = Path("rtl_repos")        # << change if needed

# ---------------------------------------------------------------------------
# 2)  PER-ACCELERATOR SPECIFICATION
# ---------------------------------------------------------------------------
ACCELERATORS = [
    # AES-256 repo has two different accelerators under sub-folders:
    {
        "name":  "aescipher",
        "files": ["aescipher.v","cipherTest.v","keyExpansion.v","sBox.v",
                  "shiftRow.v","mixColumn.v","roundlast.v","rounds.v",
                  "subBytes.v"],
        "search_hint": "Abhishake567/Verilog-Implementation-of-AES-256-algorithm/Encryption"
    },
    {
        "name":  "aesdecipher_v2",
        "files": ["aesCipher.v","inverseLastRound.v","inverseMixColumn.v",
                  "inverseRounds.v","inverseSbox.v","inverseShiftRow.v",
                  "inverseSubByte.v","keyExpansion.v","mixColumnHelper.v",
                  "sBox.v"],
        "search_hint": "Abhishake567/Verilog-Implementation-of-AES-256-algorithm/Decryption"
    },

    # ---- all remaining accelerators correspond 1-to-1 with a repo ----
    {
        "name":  "conv_new",
        "files": ["conv_new.v"],
        "search_hint": ""        # empty → search the whole tree
    },
    {
        "name":  "fcdnn_acc",
        "files": ["CoreCover.v","Core.v","FloatingPointAdder.v","FloatingPointMultiplier.v",
                  "FPExpAdder.v","FPExpMultiplier.v","FPNormal.v","FPShiftNormal.v",
                  "FPSubAdder.v","MUX_2.v","MUX_3.v","MUX_4.v","PipeReg.v",
                  "SelectableExtendablePipeReg.v","ShiftLeft.v","ShiftRight.v","SReg.v"],
        "search_hint": ""
    },
    {
        "name":  "fft_64",
        "files": ["adder.v","complex_multiplier.v","fft_64.v","FFT_block.v",
                  "memory.v","twiddle_factors.v"],
        "search_hint": ""
    },
    {
        "name":  "sha256",
        "files": ["sha256.v","sha256_w_mem.v"],
        "search_hint": ""
    },
    {
        "name":  "simple_dnn",
        "files": ["appro_func.v","dnn_soc.v","relu.v","simple_dnn.v"],
        "search_hint": ""
    },
    {
        "name":  "sobel_v2",
        "files": ["SobelFilter.v"],
        "search_hint": ""
    },
]

# ---------------------------------------------------------------------------
# 3)  DESTINATION ROOT
# ---------------------------------------------------------------------------
DEST_ROOT = Path("selected_accelerator_files")

# ---------------------------------------------------------------------------
# 4)  IMPLEMENTATION
# ---------------------------------------------------------------------------
def find_file(start_dir: Path, filename: str) -> Optional[Path]:
    """Return the *first* match for filename (case-insensitive) under start_dir,
    or None if not found."""
    lower = filename.lower()
    for path in start_dir.rglob('*'):
        if path.is_file() and path.name.lower() == lower:
            return path
    return None

def move_file(src: Path, dest_dir: Path) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name
    shutil.copy2(src, dest)
    print(f"[OK] {src.relative_to(BASE_RTL_ROOT)} → {dest.relative_to(DEST_ROOT)}")

def process_accelerator(acc) -> None:
    acc_name   = acc["name"]
    file_list  = acc["files"]
    sub_hint   = acc.get("search_hint", "")

    search_root = (BASE_RTL_ROOT / sub_hint) if sub_hint else BASE_RTL_ROOT
    dest_dir    = DEST_ROOT / acc_name

    print(f"\n=== {acc_name} ===")
    for fname in file_list:
        match = find_file(search_root, fname)
        if match is None:
            print(f"[WARN] Missing {fname}")
        else:
            move_file(match, dest_dir)

def main():
    if not BASE_RTL_ROOT.exists():
        raise SystemExit(f"ERROR: {BASE_RTL_ROOT} does not exist")

    for acc in ACCELERATORS:
        process_accelerator(acc)

if __name__ == "__main__":
    main()
