from datasets import load_dataset
import os

# -----------------------------------------------------------------------------
# Helper: write one snippet to disk, making parent folders on demand
# -----------------------------------------------------------------------------
def _write_snippet(base_dir: str, repo_name: str, rel_path: str, code: str) -> str:
    """
    base_dir   – root directory where everything is emitted
    repo_name  – e.g. 'Abhishake567/Verilog-Implementation-of-AES-256-algorithm'
    rel_path   – path inside the repo pulled from the dataset (e.g. 'Decryption/aesCipher.v')
    code       – Verilog / SystemVerilog / VHDL text to write
    returns    – full absolute path that was written
    """
    full_path = os.path.join(base_dir, repo_name, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w") as f:
        f.write(code)
    return full_path


# -----------------------------------------------------------------------------
# Main routine: dump every file for the requested repo from a HuggingFace split
# -----------------------------------------------------------------------------
def dump_repo_split(split_name: str,
                    repo_name: str,
                    base_dir: str = "rtl_repos") -> None:
    """
    split_name – 'train' | 'test' | etc.
    repo_name  – repo you want to extract, exactly as in the dataset
    base_dir   – where to mirror the repo tree on your local disk
    """
    dataset = load_dataset("ahmedallam/RTL-Repo", split=split_name)

    num_files = 0
    for sample in dataset:
        if sample["repo_name"] != repo_name:
            continue

        # Every sample has a list of dicts with 'path' and 'snippet'
        for file_info in sample["context"]:
            target = _write_snippet(base_dir,
                                    repo_name,
                                    file_info["path"],
                                    file_info["snippet"])
            num_files += 1
            print(f"[{split_name}] wrote {target}")

    if num_files == 0:
        print(f"[{split_name}] no rows found for {repo_name}")
    else:
        print(f"[{split_name}] finished – {num_files} files written")



if __name__ == "__main__":
    target_repo_list = ["NikhilRout/FPGAedgeDETECTION", "Sibonji/sha-256",
    "YutongChenVictor/simple-dnn4fpga",
    "NikhilRout/FPGAedgeDETECTION",
    "Dhruv-Kumar-1/64-point_FFT",
    "SamanMohseni/FCDNNAccelerator",
    "Dino-0625/verilog_2019_priliminary_Conv",
    "Abhishake567/Verilog-Implementation-of-AES-256-algorithm",
    "Abhishake567/Verilog-Implementation-of-AES-256-algorithm" ]
    # TARGET_REPO = "NikhilRout/FPGAedgeDETECTION"
    for target_repo in target_repo_list:
        dump_repo_split("train", target_repo)
        dump_repo_split("test",  target_repo)
