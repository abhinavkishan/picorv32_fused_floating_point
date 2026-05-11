# picorv32_fused_floating_point

**Fused Floating-Point Co-Processors with N-Element Dot-Product Extension — PCPI Interface for RISC-V**

> IIIT Bangalore &nbsp;·&nbsp; Mohit Jagini (IMT2023528) &nbsp;·&nbsp; Hardhik Dhavala (IMT2023579) &nbsp;·&nbsp; Abhinav Kishan (IMT2023580)

---

## What This Project Does

This project integrates three custom IEEE-754 single-precision floating-point co-processor units into the open-source [PicoRV32](https://github.com/YosysHQ/picorv32) RISC-V core using the **Pico Co-Processor Interface (PCPI)**. When the CPU fetches a custom instruction it cannot decode, it hands it off to the co-processor via the PCPI handshake — no compiler changes required.

| Co-Processor | Operation | Opcode | funct3 |
|---|---|---|---|
| `picorv32_pcpi_fusedfp` | `F = A×B ± C` (FMA / NMS) | `0110011` | `001` |
| `picorv32_pcpi_dotp` | `F = (A×B) + (C×D)` | `0001011` | `010` |
| `picorv32_pcpi_nfp` | `F = Σ A[i]×B[i]` (N elements from register file) | `0001011` | `111` |

**Verified simulation result:**
`[1.5, 2.5, 3.0, 4.0] · [1.0, 2.0, 3.0, 4.0] = 31.5` → `0x41FC0000` ✓

---

## Repository Structure

```
picorv32_fused_floating_point/
│
├── Design Sources/                      ← 23 Verilog files
│   │
│   ├── ── PicoRV32 Core ──
│   ├── picorv32.v                       Modified PicoRV32 core (PCPI extensions added)
│   ├── picorv32_axi.v                   AXI4-Lite wrapper  ◄─ SYNTHESIS TOP MODULE
│   ├── picorv32_axi_adapter.v           AXI protocol adapter
│   ├── picorv32_regs.v                  Register file
│   ├── picorv32_wb.v                    Wishbone bus wrapper
│   │
│   ├── ── PCPI Co-Processor Wrappers ──
│   ├── pcpiFusedFP.v                    FMA/NMS co-processor    (uses mainMod)
│   ├── pcpi_dotp.v                      4-operand dot product   (uses mainMod)
│   ├── pcpi_n_fp.v                      N-element dot product   (uses fp_mul_stub + fp_add_stub)
│   │
│   ├── ── Heavyweight Dadda FMA Datapath (shared by fusedfp + dotp) ──
│   ├── mainMod.v                        Top-level FMA arithmetic core
│   ├── fused_fp_mul.v                   Fused FP multiply datapath
│   ├── dadda.v                          Dadda multiplier tree (Booth encode + CSA reduce)
│   ├── KSA.v                            Kogge-Stone carry-select adder (48-bit)
│   ├── expCompare.v                     Exponent comparator and alignment
│   ├── opSelect.v                       FMA / NMS operation selector
│   │
│   ├── ── Lightweight Stub FP Units (used by pcpi_n_fp only) ──
│   ├── fmulstub.v                       fp_mul_stub + fp_add_stub (combinational, zero-latency)
│   ├── faddstub.v                       (placeholder — logic is inside fmulstub.v)
│   │
│   ├── ── Standard PCPI Baseline Modules ──
│   ├── picorv32_pcpi_div.v              Integer divide
│   ├── picorv32_pcpi_fmul.v             Standalone FP multiply
│   ├── picorv32_pcpi_fadd.v             Standalone FP add
│   ├── picorv32_pcpi_mul.v              Integer multiply
│   ├── picorv32_pcpi_fast_mul.v         Fast integer multiply
│   │
│   └── ── Development Stubs (not used in simulation) ──
│       ├── fusd_datapath_fake.v         Placeholder — can be ignored
│       └── fakefusedfmul.v              Placeholder — can be ignored
│
├── Simulation Sources/                  ← 2 Verilog files
│   ├── testbench.v                      System-level testbench  ◄─ SIMULATION TOP MODULE
│   └── fusedTEST.v                      Unit testbench for mainMod standalone
│
├── waveform.png                         Vivado XSim waveform screenshot (see Results section)
└── README.md
```

---

## Top Modules

| Vivado Context | Top Module | File | Folder |
|---|---|---|---|
| **Behavioral Simulation** | `testbench` | `testbench.v` | `Simulation Sources/` |
| **Synthesis / Implementation** | `picorv32_axi` | `picorv32_axi.v` | `Design Sources/` |
| **mainMod unit test** | `mainMod_tb` | `fusedTEST.v` | `Simulation Sources/` |

---

## Architecture

### High-Level Pipeline

```
                   PR0              PR1                PR2                    PR3
RISC-V Core ──►  PCPI        ──►  Decode       ──►  Read Operands  ──►  Compute       ──►  Writeback  ──►  RISC-V Core
                 Interface         fusedfp             3-operand           mainMod                          Reg file
                                   dotp                4-operand           (Dadda/KSA)
                                   N-FP (new)          Reg advance         fp_mul+add
                                                                           (N-FP path)
                 ◄────────────────────────── pcpi_wait / pcpi_ready (stall feedback) ───────────────────────
```

### N-FP FSM (5 States)

```
S_IDLE ──► S_READ ──► S_MUL ──► S_ADD ─── (i == N-1) ──► S_DONE ──► S_IDLE
              ▲                    │
              └────────────────────┘
               (i < N-1, loop next element)
```

| State | Action |
|---|---|
| `S_IDLE` | Wait for valid N-FP instruction; latch N from `insn[31:27]`; clear accumulator to 0 |
| `S_READ` | Latch A[i]/B[i] from `pcpi_rs1`/`pcpi_rs2`; assert `mul_start`; pulse `pcpi_read` if i < N−1 |
| `S_MUL` | Wait for `mul_done`; feed `mul_result` + accumulator to adder; assert `add_start` |
| `S_ADD` | Wait for `add_done`; update accumulator; if i == N−1 → `S_DONE`, else → `S_READ` |
| `S_DONE` | Assert `pcpi_wr` + `pcpi_ready`; drive accumulator on `pcpi_rd`; deassert `pcpi_wait` |

**Execution time:** 3N + 1 clock cycles &nbsp;(N=4 with zero-latency stubs → 13 cycles)

### N-FP Custom Instruction Bit Layout

```
  31   27  26 25  24    20  19    15  14  12  11     7  6       0
 ┌───────┬──────┬────────┬────────┬──────┬────────┬─────────┐
 │   N   │  00  │  rs2   │  rs1   │ 111  │   rd   │ 0001011 │
 └───────┴──────┴────────┴────────┴──────┴────────┴─────────┘
  [4:0]           B base   A base  funct3   dest    opcode
```

Testbench example (N=4, A[ ] at x1, B[ ] at x10, result in x20):
```verilog
32'b00100_00_01010_00001_111_10100_0001011   // 0x20A0FA0B
```

---

## PicoRV32 Modifications (`picorv32.v`)

| Addition | Purpose |
|---|---|
| `parameter ENABLE_FUSED_FP = 1` | Gates `picorv32_pcpi_fusedfp` instantiation |
| `parameter ENABLE_DOT_FP = 1` | Gates `picorv32_pcpi_dotp` instantiation |
| `parameter ENABLE_N_FP = 1` | Gates `picorv32_pcpi_nfp` instantiation |
| `reg [4:0] pcpi_rs1_idx` | Current register index for A[i]; incremented each `pcpi_N_read` |
| `reg [4:0] pcpi_rs2_idx` | Current register index for B[i] |
| `reg pcpi_read_active` | Set when `pcpi_valid` rises; enables index-increment logic |
| `wire pcpi_N_read` | `= ENABLE_N_FP && pcpi_n_read`; triggers index increment |
| `cpuregs_raddr1/2` steering | Redirected to `pcpi_rs1_idx`/`pcpi_rs2_idx` whenever `pcpi_valid` is high |

---

## Simulation Results

### Waveform

![Simulation Waveform](waveform.png)

The waveform shows the complete execution sequence:
1. Instruction fetch of the 16 `lui`/`addi` operand-load instructions
2. PCPI stall period (13 cycles) while the N-FP co-processor runs
3. Post-stall fetch of the `sw` and `ebreak` instructions
4. Memory write of the result at `t ≈ 1968 ns`

**Key signals at cursor `t = 1968.090 ns`:**

| Signal | Value | Meaning |
|---|---|---|
| `mem_wdata[31:0]` | **`0x41FC0000`** | IEEE-754 encoding of **31.5** ✓ |
| `mem_addr[31:0]` | `0x20000014` | Store destination address |
| `mem_wstrb[3:0]` | `0xF` | Full 32-bit word store |

### TCL Console Output

```
ifetch 0x00000000: 0x3fc000b7   # lui  x1,  0x3FC00   → x1  = 1.5
ifetch 0x00000004: 0x00008093   # addi x1,  x1,  0
ifetch 0x00000008: 0x40200137   # lui  x2,  0x40200   → x2  = 2.5
ifetch 0x0000000c: 0x00010113   # addi x2,  x2,  0
ifetch 0x00000010: 0x404001b7   # lui  x3,  0x40400   → x3  = 3.0
ifetch 0x00000014: 0x00018193   # addi x3,  x3,  0
ifetch 0x00000018: 0x40800237   # lui  x4,  0x40800   → x4  = 4.0
ifetch 0x0000001c: 0x00020213   # addi x4,  x4,  0
ifetch 0x00000020: 0x3f800537   # lui  x10, 0x3F800   → x10 = 1.0
ifetch 0x00000024: 0x00050513   # addi x10, x10, 0
ifetch 0x00000028: 0x400005b7   # lui  x11, 0x40000   → x11 = 2.0
ifetch 0x0000002c: 0x00058593   # addi x11, x11, 0
ifetch 0x00000030: 0x40400637   # lui  x12, 0x40400   → x12 = 3.0
ifetch 0x00000034: 0x00060613   # addi x12, x12, 0
ifetch 0x00000038: 0x408006b7   # lui  x13, 0x40800   → x13 = 4.0
ifetch 0x0000003c: 0x00068693   # addi x13, x13, 0
ifetch 0x00000040: 0x20a0fa0b   # N-FP instruction (N=4, rs1=x1, rs2=x10, rd=x20)
                                # ← CPU stalls here for 13 cycles
ifetch 0x00000044: 0x20000ab7   # lui  x21, 0x200
ifetch 0x00000048: 0x014aaa23   # sw   x20, 0(x21)
write  0x20000014: 0x41fc0000   # ← dot product result = 31.5 = 0x41FC0000  ✓
ifetch 0x0000004c: 0x00100073   # ebreak
```

### Accumulation Trace

| Iteration | Computation | Accumulator (hex) | Value |
|---|---|---|---|
| 0 | 1.5 × 1.0 + 0 | `0x3FC00000` | 1.5 |
| 1 | 2.5 × 2.0 + 1.5 | `0x40D00000` | 6.5 |
| 2 | 3.0 × 3.0 + 6.5 | `0x41780000` | 15.5 |
| 3 | 4.0 × 4.0 + 15.5 | `0x41FC0000` | **31.5** ✓ |

---

## How to Reproduce in Vivado

### Requirements

- Xilinx Vivado **2019.2 or later** (any edition including free WebPACK)
- No board files, no IP cores, no license files needed
- **No constraint files (`.xdc`)** — this is a pure behavioral simulation

---

### Step 1 — Create a new Vivado project

```
File → New Project
  Project name : picorv32_fused_floating_point
  Project type : RTL Project
  ☐ Do not specify sources at this time   ← tick this
  Part         : any  (e.g. xc7a35tcpg236-1)
                 (part choice does not affect behavioral simulation)
```

---

### Step 2 — Add Design Sources

In the Sources panel:
```
Click "+" (Add Sources) → Add or Create Design Sources → Add Files
```

Select **all 23 files** from the `Design Sources/` folder:

```
KSA.v                       dadda.v                 expCompare.v
faddstub.v                  fakefusedfmul.v          fmulstub.v
fusd_datapath_fake.v        fused_fp_mul.v           mainMod.v
opSelect.v                  pcpiFusedFP.v            pcpi_dotp.v
pcpi_n_fp.v                 picorv32.v               picorv32_axi.v
picorv32_axi_adapter.v      picorv32_pcpi_div.v      picorv32_pcpi_fadd.v
picorv32_pcpi_fast_mul.v    picorv32_pcpi_fmul.v     picorv32_pcpi_mul.v
picorv32_regs.v             picorv32_wb.v
```

> In the Sources panel, right-click **`picorv32_axi`** → **Set as Top**

---

### Step 3 — Add Simulation Sources

```
Click "+" (Add Sources) → Add or Create Simulation Sources → Add Files
```

Select **both files** from the `Simulation Sources/` folder:

```
testbench.v
fusedTEST.v
```

> In the Sources panel, expand **`Simulation Sources → sim_1`**, right-click **`testbench`** → **Set as Top**

---

### Step 4 — Run behavioral simulation

```
Flow → Run Simulation → Run Behavioral Simulation
```

When the Vivado simulator window opens, type in the TCL console at the bottom:

```tcl
run 15000ns
```

---

### Step 5 — Verify the result

**TCL console** — look for this line:
```
write  0x20000014: 0x41fc0000
```

**Waveform viewer** — zoom to `t ≈ 1968 ns` and verify:

| Signal | Expected |
|---|---|
| `mem_wdata[31:0]` | `41fc0000` |
| `mem_addr[31:0]` | `20000014` |
| `mem_wstrb[3:0]` | `f` |

Both confirm the dot product returned **31.5 = 0x41FC0000**. ✓

---

## Simulation Settings Summary

| Setting | Value |
|---|---|
| Timescale | `1 ns / 1 ps` |
| Clock period | 10 ns (100 MHz) |
| Reset deasserts after | 100 clock cycles (1000 ns) |
| Simulation run command | `run 15000ns` |
| Result write appears at | ≈ 1968 ns |
| Constraint files `.xdc` | **None** |
| Simulator | Vivado XSim — behavioral only |

---

## References

- [PicoRV32 by Claire Wolf](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [IEEE 754-2019 — Floating-Point Arithmetic](https://ieeexplore.ieee.org/document/8766229)
- L. Dadda, "Some schemes for parallel multipliers," *Alta Frequenza*, vol. 34, pp. 349–356, 1965.

---

## Authors

| Name | Roll No. | Email |
|---|---|---|
| Mohit Jagini | IMT2023528 | mohit.jagini@iiitb.ac.in |
| Hardhik Dhavala | IMT2023579 | hardhik.dhavala@iiitb.ac.in |
| Abhinav Kishan | IMT2023580 | abhinav.kishan@iiitb.ac.in |

IIIT Bangalore — Digital Design / Telecommunications Coursework
