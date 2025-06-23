#!/usr/bin/env python3
"""
Strict RTL copier for ESP integration.

Only copies RTL files to the ESP tree **if the destination directory already exists**.

From:
  selected_accelerator_files/<ACCNAME>/

To:
  esp/accelerators/rtl/<ACCNAME>_rtl/hw/src/<ACCNAME>_rtl_basic_dma64/
"""

import shutil
from pathlib import Path

# ---------------------------------------------------------------------------
# Path configuration
# ---------------------------------------------------------------------------
SRC_ROOT  = Path("selected_accelerator_files")   # Where the collected accelerator files live
ESP_ROOT  = Path("esp/accelerators/rtl")         # Root of ESP RTL tree

ACCELERATOR_NAMES = [
    "aescipher",
    "aesdecipher_v2",
    "conv_new",
    "fcdnn_acc",
    "fft_64",
    "sha256",
    "simple_dnn",
    "sobel_v2",
]

# ---------------------------------------------------------------------------
# Copy one accelerator’s files if destination exists
# ---------------------------------------------------------------------------
def copy_to_esp(acc_name: str) -> None:
    src_dir = SRC_ROOT / acc_name
    if not src_dir.exists():
        print(f"[WARN] Source directory not found: {src_dir}")
        return

    dest_dir = ESP_ROOT / f"{acc_name}_rtl" / "hw" / "src" / f"{acc_name}_rtl_basic_dma64"
    if not dest_dir.exists():
        print(f"[WARN] Destination does not exist, skipping: {dest_dir}")
        return

    for file_path in src_dir.iterdir():
        if file_path.is_file():
            dest_path = dest_dir / file_path.name
            shutil.copy2(file_path, dest_path)
            print(f"[OK] {file_path.relative_to(SRC_ROOT)} → {dest_path.relative_to(ESP_ROOT.parent)}")

# ---------------------------------------------------------------------------
# Main routine
# ---------------------------------------------------------------------------
def main():
    for acc in ACCELERATOR_NAMES:
        print(f"\n=== {acc} ===")
        copy_to_esp(acc)

if __name__ == "__main__":
    main()

