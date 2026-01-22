# UART Top Module Design Specification

**Document Version:** 1.0  
**Date:** January 22, 2026  
**Module Name:** `uart_top`  
**Target Platform:** Xilinx Zynq-7000 (Arty Z7)  

---

## 1. OVERVIEW

### 1.1 Purpose
This document specifies the design of a Universal Asynchronous Receiver/Transmitter (UART) top-level module intended for integration with Zynq SoC systems. The module provides a standard serial communication interface with FIFO buffering and AXI-Stream compatible handshaking.

### 1.2 Scope
The UART module supports:
- Full-duplex serial communication
- Configurable baud rate up to 115.2 kbps
- AXI-Stream compatible CPU interface
- FIFO buffering for TX and RX paths
- Parity and stop bit configuration
- Error detection and status reporting

### 1.3 Design Goals
- **Performance:** Achieve 115.2 kbps throughput with minimal latency
- **Reliability:** Metastability protection and error detection
- **Integration:** Standard handshaking protocol for easy CPU integration
- **Efficiency:** Minimal resource usage with configurable parameters
- **Maintainability:** Modular architecture with clear interfaces

---

## 2. FEATURES

### 2.1 Core Features
- ✅ Full-duplex UART communication
- ✅ AXI-Stream compatible handshaking (valid/ready)
- ✅ Separate TX and RX FIFO buffers (16-deep)
- ✅ Configurable data width (5-9 bits, default 8)
- ✅ Configurable baud rate (default 115.2 kbps)
- ✅ Configurable parity (none/even/odd)
- ✅ Configurable stop bits (1 or 2)
- ✅ Standard UART framing with 1x TX and 16x RX oversampling
- ✅ 3-stage input synchronizer for metastability protection
- ✅ Frame error detection (parity + stop bit)
- ✅ Timeout error detection
- ✅ Status signal outputs (busy, FIFO flags, errors)

### 2.2 Not Implemented
- ❌ Hardware flow control (RTS/CTS)
- ❌ DMA support
- ❌ Interrupt generation
- ❌ Auto-baud detection
- ❌ Multi-drop/9-bit mode
- ❌ Break detection/generation

---

## 3. ARCHITECTURE

### 3.1 Block Diagram

```
                    uart_top
    ┌─────────────────────────────────────────────┐
    │                                             │
    │  ┌─────────────┐                            │
    │  │  BAUD_GEN   │                            │
    │  │  TX: 1x     │                            │
    │  │  RX: 16x    │                            │
    │  └──┬──────┬───┘                            │
    │     │      │                                │
    │     │      │                                │
    │  ┌──▼──┐ ┌─▼──┐                            │
    │  │ TX  │ │ RX │                            │
    │  │PATH │ │PATH│                            │
    │  └──┬──┘ └─┬──┘                            │
    │     │      │                                │
    │ CPU │FIFO  │FIFO  UART                      │
    │  ├──▼──┐ ┌▼───┐ ┌─────┐                    │
    │  │TX   │ │RX  │ │TX   │                    │
    │  │FIFO │ │FIFO│ │ RX  │                    │
    │  │16   │ │16  │ │LOGIC│                    │
    │  └──┬──┘ └┬───┘ └─┬─┬─┘                    │
    │     │     │       │ │                       │
    │  ◄──┴──►◄─┴──►   │ │                       │
    │   AXI-Stream     │ │                       │
    │   Interface      │ │                       │
    │                  │ │                       │
    │                 TXD RXD                     │
    └──────────────────┼─┼───────────────────────┘
                       │ │
                     Physical
                     UART Lines
```

### 3.2 Module Hierarchy

```
uart_top
├── baud_gen          (Baud rate generator)
│   ├── TX divider    (1x baud rate)
│   └── RX divider    (16x oversampling)
├── asyn_fifo (TX)    (Transmit FIFO buffer)
├── uart_tx           (UART transmitter)
│   └── FSM           (START/DATA/PARITY/STOP states)
├── asyn_fifo (RX)    (Receive FIFO buffer)
└── uart_rx           (UART receiver)
    ├── Synchronizer  (3-stage metastability protection)
    ├── Start detect  (Edge detection)
    └── FSM           (START/DATA/PARITY/STOP states)
```

---

## 4. INTERFACE SPECIFICATION

### 4.1 Port List

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock and Reset** ||||
| `clk` | Input | 1 | System clock (125 MHz) |
| `rst_n` | Input | 1 | Active-low asynchronous reset |
| **UART Physical Interface** ||||
| `rxd` | Input | 1 | UART receive data line |
| `txd` | Output | 1 | UART transmit data line |
| **CPU TX Interface (AXI-Stream)** ||||
| `cpu_tx_data` | Input | 8 | Transmit data from CPU |
| `cpu_tx_valid` | Input | 1 | CPU has valid data to send |
| `cpu_tx_ready` | Output | 1 | UART ready to accept data |
| **CPU RX Interface (AXI-Stream)** ||||
| `cpu_rx_data` | Output | 8 | Received data to CPU |
| `cpu_rx_valid` | Output | 1 | UART has valid received data |
| `cpu_rx_ready` | Input | 1 | CPU ready to accept data |
| **Status Signals** ||||
| `tx_busy` | Output | 1 | Transmitter is sending frame |
| `rx_busy` | Output | 1 | Receiver is receiving frame |
| `tx_fifo_full` | Output | 1 | TX FIFO is full |
| `tx_fifo_empty` | Output | 1 | TX FIFO is empty |
| `rx_fifo_empty` | Output | 1 | RX FIFO is empty |
| `frame_error` | Output | 1 | Frame error detected (parity/stop) |
| `timeout_error` | Output | 1 | RX timeout error |

### 4.2 Parameters

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `DATA_WIDTH` | integer | 8 | 5-9 | Data bits per frame |
| `INTERNAL_CLOCK` | integer | 125,000,000 | >0 | System clock frequency (Hz) |
| `BAUD_RATE` | integer | 115,200 | >0 | UART baud rate (bps) |
| `FIFO_DEPTH` | integer | 16 | 4-256 | FIFO depth (entries) |
| `PARITY_TYPE` | integer | 1 | 0-2 | 0=none, 1=even, 2=odd |
| `STOP_BITS` | integer | 2 | 1-2 | Number of stop bits |

---

## 5. FUNCTIONAL DESCRIPTION

### 5.1 Transmit Path (TX)

#### 5.1.1 Data Flow
```
CPU → TX FIFO → UART TX → TXD Line
```

#### 5.1.2 Operation Sequence
1. **CPU Write:**
   - CPU asserts `cpu_tx_valid` with data on `cpu_tx_data`
   - Wait for `cpu_tx_ready = 1`
   - Transfer occurs when both signals high

2. **FIFO Buffering:**
   - Data stored in 16-entry FIFO
   - `cpu_tx_ready = 0` when FIFO full
   - Automatic read control: `tx_fifo_rd_en = tx_ready && !tx_fifo_empty`

3. **UART Transmission:**
   - State machine: IDLE → START → DATA → PARITY → STOP → IDLE
   - 1x baud rate timing
   - Frame format: `[START(0)][D0-D7][PARITY][STOP1][STOP2]`

#### 5.1.3 Timing
- Bit period: 8.68 μs @ 115.2 kbps
- Frame time: 104.16 μs (12 bits with parity + 2 stop)
- Max throughput: ~9,600 bytes/sec

### 5.2 Receive Path (RX)

#### 5.2.1 Data Flow
```
RXD Line → UART RX → RX FIFO → CPU
```

#### 5.2.2 Operation Sequence
1. **Signal Conditioning:**
   - 3-stage synchronizer for metastability protection
   - Start bit edge detection (1→0 transition)

2. **Data Reception:**
   - 16x oversampling for accurate sampling
   - Sample at middle of bit time (position 7/15)
   - State machine: IDLE → START → DATA → PARITY → STOP → IDLE

3. **FIFO Buffering:**
   - Valid data written to 16-entry FIFO
   - `cpu_rx_valid = 1` when data available
   - CPU controls read with `cpu_rx_ready`

4. **Error Checking:**
   - Parity calculation and comparison
   - Stop bit validation
   - Frame error asserted on mismatch

#### 5.2.3 Timing
- Oversampling period: 0.544 μs (16x rate)
- Start bit detection within 8.68 μs
- Frame reception: 104.16 μs
- Timeout: 2.08 ms (20 character times)

### 5.3 Baud Rate Generation

#### 5.3.1 TX Baud Clock (1x)
```
TX_DIVISOR = INTERNAL_CLOCK / BAUD_RATE
           = 125,000,000 / 115,200
           = 1085 (rounded)

baud_tx_en pulse every 1085 system clocks
Period = 8.68 μs
```

#### 5.3.2 RX Baud Clock (16x)
```
RX_DIVISOR = INTERNAL_CLOCK / (BAUD_RATE × 16)
           = 125,000,000 / (115,200 × 16)
           = 68 (rounded)

baud_rx_en pulse every 68 system clocks
Period = 0.544 μs (16 samples per bit)
```

### 5.4 FIFO Operation

#### 5.4.1 Configuration
- Type: Synchronous (same clock domain)
- Depth: 16 entries
- Width: 8 bits (configurable via DATA_WIDTH)
- Style: Normal (not registered)
- CDC: Bypassed (NUM_SYNC_FF = 0)

#### 5.4.2 Handshaking
Both TX and RX FIFOs use standard valid/ready handshaking:
- Transfer occurs when: `valid && ready`
- Backpressure: `ready = 0` when full (TX) or empty (RX)

### 5.5 Error Detection

#### 5.5.1 Frame Error
```
frame_error = parity_error | stop_bit_error
```
- **Parity Error:** Calculated parity ≠ Received parity
- **Stop Bit Error:** Expected '1', received '0'
- Asserted for one clock cycle on error detection

#### 5.5.2 Timeout Error
```
TIMEOUT_CYCLES = 16 × 20 = 320 RX baud ticks
               ≈ 20 character times
               ≈ 2.08 ms @ 115.2 kbps
```
- Detects when RX transaction takes too long
- Useful for protocol framing

---

## 6. TIMING DIAGRAMS

### 6.1 TX Transaction (AXI-Stream)

```
clk         __|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__

cpu_tx_valid ____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_______________

cpu_tx_ready ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

cpu_tx_data  --------< 0xA5 >-----------------------
                      ^
                    Transfer
```

### 6.2 RX Transaction (AXI-Stream)

```
clk         __|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__

cpu_rx_valid ____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_______________

cpu_rx_ready ________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_____________

cpu_rx_data  --------< 0x5A >-----------------------
                      ^
                    Transfer
```

### 6.3 UART Frame Format

```
Standard Frame (8N2 + Parity):

      Start   Data Bits (LSB first)    Parity  Stop
       Bit    D0 D1 D2 D3 D4 D5 D6 D7    Bit   Bits
        |     |  |  |  |  |  |  |  |      |    | |
TXD:  ‾‾‾|____|__|__|__|__|__|__|__|__|____|‾‾‾‾‾‾‾‾‾‾‾
        Idle  0  1  0  1  0  1  0  1    Even  1 1  Idle
              <---- 8.68μs per bit ---->

Total: 12 bits = 104.16 μs @ 115.2 kbps
```

---

## 7. PROTOCOL SPECIFICATION

### 7.1 AXI-Stream Handshake Protocol

#### 7.1.1 Valid-Ready Rules
1. **Master (source) rules:**
   - Assert `valid` when data available
   - Hold `valid` until `ready` asserts
   - Data must be stable while `valid` high

2. **Slave (sink) rules:**
   - Assert `ready` when can accept data
   - May deassert `ready` to apply backpressure
   - Transfer complete when `valid && ready`

#### 7.1.2 TX Interface (CPU → UART)
- CPU is master, UART is slave
- `cpu_tx_valid` = CPU has data
- `cpu_tx_ready` = FIFO not full
- Transfer: `cpu_tx_valid && cpu_tx_ready`

#### 7.1.3 RX Interface (UART → CPU)
- UART is master, CPU is slave
- `cpu_rx_valid` = FIFO has data
- `cpu_rx_ready` = CPU ready
- Transfer: `cpu_rx_valid && cpu_rx_ready`

### 7.2 UART Physical Layer

#### 7.2.1 Electrical
- Logic levels: CMOS/TTL compatible
- Idle state: Logic high ('1')
- Start bit: Logic low ('0')
- Mark: Logic high, Space: Logic low

#### 7.2.2 Framing
```
Bit Position:  0     1-8      9       10-11
             START  DATA   PARITY   STOP
Value:        0    D0-D7   Even/Odd  1,1
Duration:    1bit  8bits    1bit    2bits
```

---

## 8. PERFORMANCE SPECIFICATIONS

### 8.1 Throughput

| Configuration | Bits/Frame | Frame Time | Throughput |
|---------------|------------|------------|------------|
| 8N1 | 10 | 86.8 μs | 11,520 B/s |
| 8N2 | 11 | 95.5 μs | 10,472 B/s |
| 8E1 | 11 | 95.5 μs | 10,472 B/s |
| **8E2** (default) | **12** | **104.2 μs** | **9,600 B/s** |

### 8.2 Latency

| Path | Min Latency | Max Latency | Notes |
|------|-------------|-------------|-------|
| CPU → TXD | 104 μs | 1.77 ms | FIFO empty / full |
| RXD → CPU | 104 μs | 1.77 ms | Direct / FIFO full |
| TX FIFO write | 1 clock | 1 clock | 8 ns @ 125 MHz |
| RX FIFO read | 1 clock | 1 clock | 8 ns @ 125 MHz |

### 8.3 Clock Domain

| Domain | Frequency | Period | Source |
|--------|-----------|--------|--------|
| System | 125 MHz | 8 ns | Input clock |
| TX Baud | 115.2 kHz | 8.68 μs | Generated (÷1085) |
| RX Baud | 1.8432 MHz | 0.544 μs | Generated (÷68) |

### 8.4 Resource Utilization (Estimated)

| Resource | Quantity | Notes |
|----------|----------|-------|
| LUTs | ~200 | Combinational logic |
| FFs | ~150 | Sequential elements |
| BRAM | 0 | FIFOs use distributed RAM |
| DSP | 0 | No multipliers needed |

---

## 9. ERROR HANDLING

### 9.1 Error Types

| Error | Detection | Recovery | Status Signal |
|-------|-----------|----------|---------------|
| **Parity Error** | Calculated ≠ Received | Data still in FIFO | `frame_error` |
| **Stop Bit Error** | Expected '1', got '0' | Data discarded | `frame_error` |
| **Timeout Error** | No activity > 20 chars | State reset | `timeout_error` |
| **FIFO Overflow** | Write when full | Data lost | `tx_fifo_full` |

### 9.2 Error Behavior

#### 9.2.1 Frame Error
- Parity or stop bit error detected
- Data **IS** written to RX FIFO (with error flag)
- `frame_error` asserted for 1 clock cycle
- CPU must check status to discard bad data

#### 9.2.2 Timeout Error
- RX transaction exceeds 320 baud ticks
- State machine resets to IDLE
- Partial frame discarded
- `timeout_error` asserted for 1 clock cycle

#### 9.2.3 FIFO Full Condition
- TX: CPU must check `cpu_tx_ready` before write
- RX: CPU must service FIFO to prevent data loss
- No automatic recovery

---

## 10. USAGE GUIDELINES

### 10.1 Initialization Sequence

```c
1. Assert rst_n = 0 for minimum 100ns
2. Deassert rst_n = 1
3. Wait for 1ms (FIFO initialization)
4. Begin normal operation
```

### 10.2 Transmit Example (Blocking)

```c
void uart_send_byte(uint8_t data) {
    // Wait for FIFO ready
    while (!cpu_tx_ready);
    
    // Write data
    cpu_tx_data = data;
    cpu_tx_valid = 1;
    
    // Wait 1 clock
    wait_clock();
    
    // Deassert valid
    cpu_tx_valid = 0;
}
```

### 10.3 Receive Example (Polling)

```c
uint8_t uart_recv_byte(void) {
    // Wait for data available
    while (!cpu_rx_valid);
    
    // Read data
    uint8_t data = cpu_rx_data;
    
    // Assert ready for 1 clock
    cpu_rx_ready = 1;
    wait_clock();
    cpu_rx_ready = 0;
    
    return data;
}
```

### 10.4 Error Checking

```c
if (frame_error) {
    // Discard received byte
    cpu_rx_ready = 1;  // Flush FIFO
    wait_clock();
    cpu_rx_ready = 0;
    error_count++;
}
```

---

## 11. DESIGN CONSTRAINTS

### 11.1 Timing Constraints

```tcl
# System clock
create_clock -period 8.000 [get_ports clk]

# Input delay (RXD)
set_input_delay -clock clk -max 2.0 [get_ports rxd]
set_input_delay -clock clk -min 0.0 [get_ports rxd]

# Output delay (TXD)
set_output_delay -clock clk -max 2.0 [get_ports txd]
set_output_delay -clock clk -min 0.0 [get_ports txd]

# False paths (async reset)
set_false_path -from [get_ports rst_n]
```

### 11.2 Physical Constraints

```tcl
# UART pins (Arty Z7)
set_property PACKAGE_PIN D10 [get_ports rxd]
set_property PACKAGE_PIN A9  [get_ports txd]
set_property IOSTANDARD LVCMOS33 [get_ports {rxd txd}]
```

---

## 12. VERIFICATION PLAN

### 12.1 Testbench Coverage

| Test Case | Description | Pass Criteria |
|-----------|-------------|---------------|
| **Basic RX** | Single byte receive | Data matches |
| **Multiple RX** | Sequential bytes | All data correct |
| **Back-to-back RX** | No gap between frames | No errors |
| **Basic TX** | Single byte transmit | Correct frame |
| **Multiple TX** | Sequential bytes | All frames correct |
| **RX Backpressure** | CPU slow to read | No data loss |
| **TX/RX Sequential** | Mixed operations | Both paths work |
| **FIFO Stress** | Fill/empty FIFOs | No overflow |
| **TX Burst** | Rapid sequential TX | Frames correct |
| **Error Injection** | Bad parity/stop bits | Errors detected |

### 12.2 Simulation Parameters

```systemverilog
CLK_PERIOD = 8ns       // 125 MHz
BAUD_RATE = 115200     // Standard rate
BIT_PERIOD = 8680ns    // Calculated
TEST_TIMEOUT = 50ms    // Per test
```

---

## 13. COMPLIANCE & STANDARDS

### 13.1 UART Standard Compliance

| Standard | Compliance | Notes |
|----------|------------|-------|
| **RS-232 (Logical)** | ✅ Full | Frame format compatible |
| **RS-232 (Electrical)** | ❌ N/A | Requires external transceiver |
| **3.3V TTL** | ✅ Full | Direct FPGA I/O compatible |

### 13.2 AXI-Stream Compliance

| Requirement | Status | Notes |
|-------------|--------|-------|
| Valid/Ready handshake | ✅ | Full compliance |
| No combinational paths | ✅ | Registered outputs |
| Reset behavior | ✅ | Async reset, sync deassert |

---

## 14. KNOWN LIMITATIONS

### 14.1 Current Limitations

1. **Fixed Baud Rate:** Compile-time only, no runtime change
2. **No Interrupts:** CPU must poll status
3. **No Flow Control:** No RTS/CTS hardware support
4. **Single Channel:** One TX/RX pair only
5. **Timeout Not Configurable:** Fixed at 20 character times

### 14.2 Future Enhancements

- [ ] Runtime baud rate configuration
- [ ] Interrupt generation (TX empty, RX full, errors)
- [ ] Hardware flow control (RTS/CTS)
- [ ] DMA interface support
- [ ] Break detection/generation
- [ ] Configurable timeout
- [ ] Loopback test mode

---

## 15. REVISION HISTORY

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-22 | Initial | First release with critical fixes |

---

## 16. REFERENCES

1. **RS-232 Standard:** TIA-232-F, Telecommunications Industry Association
2. **UART Tutorial:** https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter
3. **AXI-Stream Protocol:** ARM IHI 0051A, ARM Limited
4. **Xilinx Zynq-7000:** UG585, All Programmable SoC Technical Reference Manual
5. **Metastability:** Xilinx WP272, "Metastability in FPGAs"

---

## 17. APPENDIX

### A.1 Baud Rate Calculations

```
Given:
  INTERNAL_CLOCK = 125 MHz
  BAUD_RATE = 115.2 kbps

TX Calculation (1x):
  TX_DIVISOR = round(125,000,000 / 115,200)
             = round(1085.07)
             = 1085
  
  Actual TX Baud = 125,000,000 / 1085
                 = 115,207 bps
  
  Error = (115,207 - 115,200) / 115,200
        = 0.006% ✅

RX Calculation (16x):
  RX_DIVISOR = round(125,000,000 / (115,200 × 16))
             = round(67.816)
             = 68
  
  Actual RX Sample Rate = 125,000,000 / 68
                        = 1,838,235 Hz
  
  Actual RX Baud = 1,838,235 / 16
                 = 114,890 bps
  
  Error = (114,890 - 115,200) / 115,200
        = -0.27% ✅
```

### A.2 Timing Budget

```
System Clock Period:        8.00 ns
Logic Delay:               ~2.00 ns
Setup Time:                ~0.50 ns
Clock Skew:                ~0.30 ns
Margin:                    ~5.20 ns (65%)
```

### A.3 Power Estimation

```
Dynamic Power @ 125 MHz, 115.2 kbps:
  Logic:          ~5 mW
  Clock:          ~8 mW
  I/O:            ~2 mW
  Total:         ~15 mW
```

---

**End of Document**
