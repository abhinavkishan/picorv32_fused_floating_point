# picorv32_fused_floating_point

**Fused Floating-Point Co-Processors with N-Element Dot-Product Extension — PCPI Interface for RISC-V**

> IIIT Bangalore · IMT2023528 · IMT2023579 · IMT2023580

---

## Overview

This project integrates three custom IEEE-754 single-precision floating-point co-processor units into the open-source [PicoRV32](https://github.com/YosysHQ/picorv32) RISC-V core using the **Pico Co-Processor Interface (PCPI)**. The co-processors respond to custom RISC-V instructions and are activated transparently when the CPU decodes them — no modifications to the software toolchain are required.

| Module | Operation | Instruction |
|--------|-----------|-------------|
| `picorv32_pcpi_fusedfp` | Fused Multiply-Accumulate: `F = A×B ± C` (FMA / NMS) | opcode `0110011`, funct3 `001` |
| `picorv32_pcpi_dotp` | 4-Operand Dot Product: `F = (A×B) + (C×D)` | opcode `0001011`, funct3 `010` |
| `picorv32_pcpi_nfp` | N-Element Iterative Dot Product: `F = Σ A[i]×B[i]` | opcode `0001011`, funct3 `111`, N in bits [31:27] |

The simulation confirms that the N-FP module correctly computes the dot product **[1.5, 2.5, 3.0, 4.0] · [1.0, 2.0, 3.0, 4.0] = 31.5** (`0x41FC0000` in IEEE-754).

---

## Repository Structure

```
picorv32_fused_floating_point/
│
├── risc.srcs/
│   ├── sources_1/new/          ← Design Sources (24 files)
│   │   ├── picorv32.v              (Top module — modified PicoRV32 core)
│   │   ├── picorv32_axi.v          (AXI4-Lite wrapper — top for synthesis)
│   │   ├── picorv32_axi_adapter.v
│   │   ├── picorv32_regs.v
│   │   ├── picorv32_wb.v
│   │   │
│   │   ├── pcpiFusedFP.v           (PCPI wrapper — FMA/NMS co-processor)
│   │   ├── pcpi_dotp.v             (PCPI wrapper — 4-operand dot product)
│   │   ├── pcpi_n_fp.v             (PCPI wrapper — N-element dot product)
│   │   │
│   │   ├── mainMod.v               (Shared Dadda FMA arithmetic core)
│   │   ├── fused_fp_mul.v          (Fused FP multiply datapath)
│   │   ├── dadda.v                 (Dadda multiplier tree)
│   │   ├── KSA.v                   (Kogge-Stone carry-select adder)
│   │   ├── expCompare.v            (Exponent comparator / align)
│   │   ├── opSelect.v              (FMA/NMS operation selector)
│   │   │
│   │   ├── fmulstub.v              (fp_mul_stub + fp_add_stub — used by nfp)
│   │   ├── faddstub.v
│   │   │
│   │   ├── picorv32_pcpi_div.v     (Standard PCPI divide unit)
│   │   ├── picorv32_pcpi_fmul.v    (Standalone FP multiply)
│   │   ├── picorv32_pcpi_fadd.v    (Standalone FP add)
│   │   ├── picorv32_pcpi_mul.v
│   │   ├── picorv32_pcpi_fast_mul.v
│   │   │
│   │   ├── fusd_datapath_fake.v    (Development stub — not used in sim)
│   │   ├── fakefusedfmul.v         (Development stub — not used in sim)
│   │   └── testbench.v             (System-level testbench)
│   │
│   └── sim_1/new/              ← Simulation Sources (1 file)
│       └── fusedTEST.v             (Unit testbench for mainMod standalone)
│
└── README.md
```

---

## Top Modules

| Context | Top Module | File |
|---------|-----------|------|
| **Synthesis / Implementation** | `picorv32_axi` | `picorv32_axi.v` |
| **Behavioral Simulation** | `testbench` | `testbench.v` |
| **mainMod unit test** | `mainMod_tb` | `fusedTEST.v` |

> **Note:** `testbench.v` is listed under *Design Sources* in this project but is used as the simulation top module. In Vivado, ensure it is set as the top module for `sim_1`.

---

## Architecture

The architecture is documented in two views:

### (A) High-Level Pipeline

```
RISC-V Core → PCPI Interface → [PR0] → Decode → [PR1] → Read Operands
           → [PR2] → Compute (Datapath) → [PR3] → Writeback → RISC-V Core
                                   ↑
                    pcpi_wait / pcpi_ready (stall feedback)
```

Three parallel co-processor datapaths operate in the Compute stage:

| Datapath | Modules | Description |
|----------|---------|-------------|
| **Heavyweight Dadda** | `mainMod` | Booth encode → Dadda tree → CSA → KSA → LeadOne → RNE round |
| **Lightweight Stub FP** | `fp_mul_stub` + `fp_add_stub` | Combinational IEEE-754 multiply and add (used by `picorv32_pcpi_nfp`) |

### (B) N-FP FSM

The `picorv32_pcpi_nfp` control FSM:

```
S_IDLE → S_READ → S_MUL → S_ADD → S_DONE → S_IDLE
              ↑___________________________|
              (loop for i = 0..N-1)
```

| State | Action |
|-------|--------|
| `S_IDLE` | Wait for N-FP instruction; latch N; reset accumulator |
| `S_READ` | Latch A[i]/B[i]; assert `mul_start`; pulse `pcpi_read` if i < N-1 |
| `S_MUL` | Wait for `mul_done`; feed product + accumulator to adder |
| `S_ADD` | Wait for `add_done`; update accumulator; loop or go to S_DONE |
| `S_DONE` | Assert `pcpi_wr` + `pcpi_ready`; present result on `pcpi_rd` |

Total execution: **3N + 1 clock cycles** (with zero-latency stubs).

---

## Custom Instruction Encoding

### N-FP Instruction Word Layout

```
 31    27 26  25 24    20 19    15 14  12 11     7 6       0
 ┌───────┬─────┬────────┬────────┬──────┬────────┬─────────┐
 │  N    │ 00  │  rs2   │  rs1   │ 111  │   rd   │ 0001011 │
 └───────┴─────┴────────┴────────┴──────┴────────┴─────────┘
  [4:0]          B base   A base  funct3  result   opcode
```

**Example** (N=4, rs1=x1, rs2=x10, rd=x20):
```verilog
32'b00100_00_01010_00001_111_10100_0001011  // = 0x20A0FA0B
```

---

## PicoRV32 Modifications

The following changes were made to `picorv32.v` to support `picorv32_pcpi_nfp`:

| Change | Detail |
|--------|--------|
| `ENABLE_FUSED_FP` parameter | Gates `picorv32_pcpi_fusedfp` instantiation |
| `ENABLE_DOT_FP` parameter | Gates `picorv32_pcpi_dotp` instantiation |
| `ENABLE_N_FP` parameter | Gates `picorv32_pcpi_nfp` instantiation |
| `pcpi_rs1_idx [4:0]` | Register index pointer for A[i], advanced by `pcpi_N_read` |
| `pcpi_rs2_idx [4:0]` | Register index pointer for B[i] |
| `pcpi_read_active` | Set when `pcpi_valid` rises; enables index increment |
| `pcpi_N_read` wire | `ENABLE_N_FP && pcpi_n_read` — triggers index increment |
| `cpuregs_raddr1/2` | Steered to `pcpi_rs1_idx`/`pcpi_rs2_idx` during PCPI stalls |

All three co-processors default to **enabled** (`ENABLE_PCPI = 1`, `ENABLE_FUSED_FP = 1`, `ENABLE_DOT_FP = 1`, `ENABLE_N_FP = 1`).

---

## Simulation Results

### Waveform

The Vivado XSim waveform below shows the moment the dot-product result is written to memory at `t ≈ 1968 ns`:

![Simulation Waveform](waveform.png)

| Signal | Value at t = 1968.090 ns |
|--------|--------------------------|
| `mem_wdata[31:0]` | **`0x41FC0000`** = 31.5 ✓ |
| `mem_addr[31:0]` | `0x20000014` |
| `mem_wstrb[3:0]` | `0xF` (full 32-bit word) |

### Accumulation Trace

| Iteration | Computation | Accumulator (hex) | Value |
|-----------|-------------|-------------------|-------|
| 0 | 1.5 × 1.0 + 0 | `0x3FC00000` | 1.5 |
| 1 | 2.5 × 2.0 + 1.5 | `0x40D00000` | 6.5 |
| 2 | 3.0 × 3.0 + 6.5 | `0x41780000` | 15.5 |
| 3 | 4.0 × 4.0 + 15.5 | `0x41FC0000` | **31.5** ✓ |

### TCL Console Output

```
ifetch 0x00000000: 0x3fc000b7    # lui x1, 0x3FC00    → x1  = 1.5
ifetch 0x00000004: 0x00008093    # addi x1, x1, 0
ifetch 0x00000008: 0x40200137    # lui x2, 0x40200    → x2  = 2.5
ifetch 0x0000000c: 0x00010113    # addi x2, x2, 0
ifetch 0x00000010: 0x404001b7    # lui x3, 0x40400    → x3  = 3.0
ifetch 0x00000014: 0x00018193    # addi x3, x3, 0
ifetch 0x00000018: 0x40800237    # lui x4, 0x40800    → x4  = 4.0
ifetch 0x0000001c: 0x00020213    # addi x4, x4, 0
ifetch 0x00000020: 0x3f800537    # lui x10, 0x3F800   → x10 = 1.0
ifetch 0x00000024: 0x00050513    # addi x10, x10, 0
ifetch 0x00000028: 0x400005b7    # lui x11, 0x40000   → x11 = 2.0
ifetch 0x0000002c: 0x00058593    # addi x11, x11, 0
ifetch 0x00000030: 0x40400637    # lui x12, 0x40400   → x12 = 3.0
ifetch 0x00000034: 0x00060613    # addi x12, x12, 0
ifetch 0x00000038: 0x408006b7    # lui x13, 0x40800   → x13 = 4.0
ifetch 0x0000003c: 0x00068693    # addi x13, x13, 0
ifetch 0x00000040: 0x20a0fa0b    # N-FP dot product instruction (N=4)
                                 # ← CPU stalls here for 13 cycles (3×4+1)
ifetch 0x00000044: 0x20000ab7    # lui x21, 0x200
ifetch 0x00000048: 0x014aaa23    # sw x20, 0(x21)
write  0x20000014: 0x41fc0000    # ← result stored: 31.5 = 0x41FC0000 ✓
ifetch 0x0000004c: 0x00100073    # ebreak
```

---

## How to Reproduce the Simulation in Vivado

### Prerequisites

- Xilinx Vivado 2019.2 or later (any edition including WebPACK)
- No additional IP cores or board files required
- No simulation constraints (`.xdc`) — this is a pure behavioral simulation

### Step-by-Step

**1. Create a new Vivado project**
```
File → New Project → RTL Project
Part: any (e.g. xc7a35tcpg236-1 for Artix-7)
Do NOT add sources during the wizard
```

**2. Add Design Sources**

Go to `Sources → Add Sources → Add or Create Design Sources` and add **all files** from `risc.srcs/sources_1/new/`:

```
KSA.v                    dadda.v                expCompare.v
faddstub.v               fakefusedfmul.v        fmulstub.v
fusd_datapath_fake.v     fused_fp_mul.v         mainMod.v
opSelect.v               pcpiFusedFP.v          pcpi_dotp.v
pcpi_n_fp.v              picorv32.v             picorv32_axi.v
picorv32_axi_adapter.v   picorv32_pcpi_div.v    picorv32_pcpi_fadd.v
picorv32_pcpi_fast_mul.v picorv32_pcpi_fmul.v   picorv32_pcpi_mul.v
picorv32_regs.v          picorv32_wb.v          testbench.v
```

> Set **`picorv32_axi`** as the top module for Design Sources.

**3. Add Simulation Sources**

Go to `Sources → Add Sources → Add or Create Simulation Sources` and add:

```
fusedTEST.v
```

**4. Set simulation top module**

In the Sources panel:
- Expand `Simulation Sources → sim_1`
- Right-click `testbench` → **Set as Top**

**5. No constraints needed**

There are no `.xdc` constraint files for this project. The simulation is purely behavioral — no timing, no I/O pin assignments.

**6. Run simulation**

```
Flow → Run Simulation → Run Behavioral Simulation
```

In the TCL console, set the run time:
```tcl
run 15000ns
```

**7. Verify the result**

In the TCL console output look for:
```
write  0x20000014: 0x41fc0000
```

In the waveform viewer:
- Zoom to `t ≈ 1968 ns`
- Check `mem_wdata[31:0]` = `0x41FC0000`
- Check `mem_addr[31:0]` = `0x20000014`
- Check `mem_wstrb[3:0]` = `F`

All three confirm a correct dot-product result of **31.5**.

---

## Simulation Parameters Summary

| Parameter | Value |
|-----------|-------|
| Timescale | `1 ns / 1 ps` |
| Clock period | 10 ns (100 MHz) |
| Reset deassert | after 100 clock cycles |
| Simulation duration | 15,000 ns |
| Result appears at | ≈ 1,968 ns |
| Constraints file | **None** |
| Simulator | Vivado XSim (behavioral) |

---

## Module Reference

| File | Module(s) | Role |
|------|-----------|------|
| `picorv32.v` | `picorv32` | Modified PicoRV32 core with PCPI extensions |
| `picorv32_axi.v` | `picorv32_axi` | AXI4-Lite wrapper — synthesis top |
| `picorv32_axi_adapter.v` | `picorv32_axi_adapter` | AXI adapter |
| `picorv32_regs.v` | `picorv32_regs` | Register file |
| `pcpiFusedFP.v` | `picorv32_pcpi_fusedfp` | FMA/NMS co-processor (uses `mainMod`) |
| `pcpi_dotp.v` | `picorv32_pcpi_dotp` | 4-operand dot product (uses `mainMod`) |
| `pcpi_n_fp.v` | `picorv32_pcpi_nfp` | N-element dot product (uses stubs) |
| `mainMod.v` | `mainMod` | Dadda-based FMA arithmetic core |
| `fused_fp_mul.v` | `mainMod` *(alt def)* | Fused FP multiply datapath |
| `dadda.v` | `dadda` | Dadda multiplier tree |
| `KSA.v` | `KSA_8` | Kogge–Stone carry-select adder |
| `expCompare.v` | `expCompare` | Exponent comparator and alignment |
| `opSelect.v` | `opSelect` | FMA/NMS operation selector |
| `fmulstub.v` | `fp_mul_stub`, `fp_add_stub` | Lightweight combinational FP units |
| `picorv32_pcpi_div.v` | `picorv32_pcpi_div` | Integer divide co-processor |
| `picorv32_pcpi_fmul.v` | `picorv32_pcpi_fmul` | Standalone FP multiply |
| `picorv32_pcpi_fadd.v` | `picorv32_pcpi_fadd` | Standalone FP add |
| `picorv32_pcpi_mul.v` | `picorv32_pcpi_mul` | Integer multiply |
| `testbench.v` | `testbench` | System simulation top module |
| `fusedTEST.v` | `mainMod_tb` | Unit test for `mainMod` |

---

## References

- [PicoRV32 by Claire Wolf](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [IEEE 754-2019 Standard for Floating-Point Arithmetic](https://ieeexplore.ieee.org/document/8766229)
- L. Dadda, "Some schemes for parallel multipliers," *Alta Frequenza*, vol. 34, pp. 349–356, 1965.

---

## Authors

| Name | Roll No. | Email |
|------|----------|-------|
| Mohit Jagini | IMT2023528 | mohit.jagini@iiitb.ac.in |
| Hardhik Dhavala | IMT2023579 | hardhik.dhavala@iiitb.ac.in |
| Abhinav Kishan | IMT2023580 | abhinav.kishan@iiitb.ac.in |

IIIT Bangalore — Digital Design / Telecommunications Coursework
