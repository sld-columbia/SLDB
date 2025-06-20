# ![image](https://github.com/user-attachments/assets/dbe071b8-a2dc-41ed-a44a-fdb6fd64f052)

## Overview
The System-Level Design Benchmark (SLDB) is a comprehensive benchmark suite tailored to evaluate Large Language Models (LLMs) performance in system-level integration and configuration tasks for heterogeneous System-on-Chip (SoC) designs. Developed to bridge the gap between component-level benchmarks and realistic SoC scenarios, SLDB enables researchers and practitioners to assess the capabilities of LLMs in system-level design tasks.
<br>
![image](https://github.com/user-attachments/assets/c529df9f-00dc-4414-b467-3d1cc96afb98)





## Key Features

* **10 Baseline Heterogeneous SoC Designs:** Each design integrates accelerators from various application domains (cryptography, deep learning, image processing) into a baseline 2x2 tile ESP architecture.
* **Synthetic Library:** Combines baseline accelerators into various configurations.
* **Complete Integration Environment:** Full integration and configuration files, DMA wrapper templates, testing application code (baremetal and Linux-compatible).
* **Evaluation Metrics:** Provides power, area, and performance metrics from FPGA synthesis, and enables functional correctness assessments through detailed accelerator processing stages (Configuration, Load, Compute, Store).

## Accelerator Designs Included

| Accelerator    | Domain           | Description                          | Code Length | Source   |
| -------------- | ---------------- | ------------------------------------ | ----------- | -------- |
| AES Encryption | Cryptography     | AES encryption algorithm             | 13,736      | RTL-Repo |
| AES Decryption | Cryptography     | AES decryption algorithm             | 37,658      | RTL-Repo |
| SHA-256        | Cryptography     | SHA-256 hashing algorithm            | 13,343      | RTL-Repo |
| SOBEL          | Image Processing | Edge detection filter                | 1,951       | RTL-Repo |
| FFT            | Image Processing | 64-point, 9-stage FFT                | 200,911     | RTL-Repo |
| FCDNN          | Deep Learning    | 6-layer DNN with sigmoid activation  | 33,163      | RTL-Repo |
| LSTM           | Deep Learning    | Long Short-Term Memory layer         | 69,138      | Koios    |
| SIMPLEDNN      | Deep Learning    | 7-layer DNN with relu activation     | 15,420      | RTL-Repo |
| SPMV           | Deep Learning    | Sparse Matrix-Vector multiplication  | 111,074     | Koios    |
| CONVOLUTION    | Deep Learning    | 3-layer convolutional neural network | 8,937       | RTL-Repo |

## Quick Start

### Requirements

* ESP Framework ([https://www.esp.cs.columbia.edu](https://www.esp.cs.columbia.edu))
* ModelSim DE 2023.2
* Vivado 2023.2

### Installation

Clone the repository:

```bash
git clone https://github.com/sld-columbia/sldb.git
```

Navigate to the directory:

```bash
cd SLDB
```

### Running a Benchmark

1. **Select Accelerator**: Choose an accelerator from the provided list.
2. **Configure SoC**:
    1.  ```bash
        cd esp; ./tools/accgen/accgen.sh
        ```
    2. Complete the SoC configurations using the values in integrated_acc/$ACCNAME/soc_gen/$ACCNAME_accgen.txt
4. **Add Benchmark RTL to the ESP SoC**: After the SoC generation is complete, you should be able to see a folder at esp/accelerators/rtl/$ACCNAME_rtl/ containing the ESP generated templates for the accelerator code. 
    1. Copy the contents of integrated_acc/$ACCNAME/$ACCNAME_rtl into esp/accelerators/rtl/$ACCNAME_rtl/. Make sure the SoC configuration is identical to the one in the file from Step 1, otherwise compatibility issues may occur.

5. **Generating a bitstream**: 
    1.  ```bash 
        make $ACCNAME_rtl-hls
        ```
    2. ```bash 
        make esp-xconfig
        ```
    3. For the baseline SoCs, keep the default configurations and add the           
        accelerator. Make sure the selected processor is Ariane. For 
        the synthetic library SoC, use nxn tiles with accelerators and components of your choosing. You may only use one IO tile per SoC.
    
    4. ```bash 
        make $ACCNAME_rtl-baremetal
        ```
    5. For simulation:
    6. For synthesis: make vivado-syn



## Evaluation Metrics

Functional correctness is assessed through simulation against accelerator processing stages:

* **Configuration Stage:** Correct configuration parameters initialization.
* **Load Stage:** Correct handling of DMA data loading.
* **Compute Stage:** Proper computation and signal-port mappings.
* **Store Stage:** Successful DMA data storage back to memory.

## Citation

If you use the SLDB benchmark suite in your research, please cite our paper:

```
@inproceedings{SLDB_ICLAD_2025,
    title={SLDB: An End-To-End Heterogeneous System-on-Chip Benchmark Suite for LLM-Aided Design},
    author={...},
    booktitle={},
    year={2025},
    pages={...}
}
```

## Contributing

We welcome contributions and improvements. Feel free to submit pull requests and issues to help enhance SLDB.

## License

SLDB is released under the Apache 2.0 License. See the [LICENSE](LICENSE) file for details.

---

