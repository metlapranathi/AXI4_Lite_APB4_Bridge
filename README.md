# AXI4-Lite to APB4 Bridge with SystemVerilog Verification

A hands-on **RTL design and verification project** implementing an **AXI4-Lite to APB4 bridge** using **SystemVerilog**.

The project focuses on understanding and implementing the protocol conversion between:

```text
AXI4-Lite
    |
    |  Protocol Conversion
    v
APB4
```

The bridge accepts AXI4-Lite read and write transactions, converts them into APB4 transactions, waits for APB completion, and returns the corresponding result to the AXI4-Lite side.

The project also includes a **SystemVerilog verification environment** used to exercise normal transactions, protocol corner cases, response handling, wait states, error conditions, and waveform behavior.

---

## 1. Project Overview

### What problem does this project solve?

Different components inside an SoC can use different bus protocols.

For example:

```text
Processor / AXI Interconnect
          |
          | AXI4-Lite
          v
     AXI4-Lite Slave
          |
          | protocol conversion
          v
        APB4
          |
          v
      Peripheral
```

AXI4-Lite and APB4 have different transaction mechanisms.

AXI4-Lite uses:

```text
VALID / READY handshaking
```

with independent channels.

APB uses:

```text
SETUP phase
     |
     v
ACCESS phase
     |
     v
PREADY
```

Therefore they cannot simply be connected signal-for-signal.

The bridge provides the required:

```text
request capture
      +
FSM control
      +
protocol conversion
      +
response generation
```

---

# 2. Main Objectives

The main objectives of this project are:

* Understand the AXI4-Lite protocol.
* Understand the APB4 protocol.
* Understand AXI VALID/READY handshaking.
* Understand independent AXI write address and write data channels.
* Convert AXI4-Lite write transactions into APB4 writes.
* Convert AXI4-Lite read transactions into APB4 reads.
* Generate APB SETUP and ACCESS phases correctly.
* Handle APB wait states using `PREADY`.
* Propagate APB error information using `PSLVERR`.
* Handle AXI response channels.
* Handle byte strobes using `WSTRB` / `PSTRB`.
* Implement the bridge using synthesizable SystemVerilog RTL.
* Verify the bridge using a self-checking SystemVerilog testbench.
* Debug protocol behavior using simulation waveforms.

---

# 3. High-Level Architecture

```text
                         AXI4-Lite Manager
                                |
                +---------------+---------------+
                |                               |
                v                               v
        Write Channels                    Read Channel
          AW / W                              AR
                |                               |
                +---------------+---------------+
                                |
                                v
                     +----------------------+
                     |   AXI4-Lite to APB4  |
                     |       BRIDGE         |
                     |                      |
                     | Request Capture      |
                     | FSM / Control        |
                     | AXI Response Logic   |
                     +----------+-----------+
                                |
                                v
                              APB4
                                |
                                v
                         APB4 Peripheral
```

The overall transaction flow is:

```text
AXI Request
     |
     v
AXI Handshake
     |
     v
Capture Request
     |
     v
APB SETUP
     |
     v
APB ACCESS
     |
     v
Wait for PREADY
     |
     v
Capture APB Result
     |
     v
AXI Response
```

The core mental model is:

```text
CAPTURE -> TRANSLATE -> WAIT -> RESPOND
```

---

# 4. AXI4-Lite

AXI4-Lite is a simplified memory-mapped AXI interface intended primarily for control and register-style accesses.

Unlike full AXI4, AXI4-Lite uses **single-beat transactions** and does not require burst implementation.

The five AXI4-Lite channels are:

| Channel | Meaning              |
| ------- | -------------------- |
| AW      | Write Address        |
| W       | Write Data           |
| B       | Write Response       |
| AR      | Read Address         |
| R       | Read Data / Response |

The easiest way to remember them is:

```text
WRITE

AW + W
  |
  v
 B
```

and:

```text
READ

AR
 |
 v
 R
```

---

# 5. AXI VALID / READY Handshake

The most important AXI rule is:

```text
TRANSFER = VALID && READY
```

A transaction occurs on a channel when both `VALID` and `READY` are high in the same clock cycle.

For example:

```text
Cycle 1

VALID = 1
READY = 0

No transfer
```

Then:

```text
Cycle 2

VALID = 1
READY = 1

Transfer occurs
```

This rule is fundamental to the bridge and to the verification environment.

---

# 6. AXI Write Address Channel

The write address channel carries the address of a write.

Important signals include:

```text
AWADDR
AWVALID
AWREADY
```

Example:

```text
AWADDR  = 0x00000010
AWVALID = 1
AWREADY = 1
```

Because:

```text
AWVALID && AWREADY = 1
```

the write address is accepted.

The bridge must retain the address if the APB transaction happens later.

---

# 7. AXI Write Data Channel

The write data channel carries:

```text
WDATA
WSTRB
WVALID
WREADY
```

For example:

```text
WDATA  = 0xDEADBEEF
WSTRB  = 4'b1111
```

The write data is accepted when:

```text
WVALID && WREADY
```

occurs.

---

# 8. AW and W Are Independent

This is one of the most important concepts in the entire project.

The AXI write address and write data channels are independent.

Therefore the bridge must not assume:

```text
AWVALID
```

and:

```text
WVALID
```

are always asserted together.

The following are possible transaction timings:

### Case 1 — Same cycle

```text
Cycle 1:

AWVALID = 1
WVALID  = 1
```

### Case 2 — Address first

```text
Cycle 1:
AWVALID = 1

Cycle 2:
WVALID = 1
```

### Case 3 — Data first

```text
Cycle 1:
WVALID = 1

Cycle 2:
AWVALID = 1
```

Therefore the bridge needs internal storage for the information it has already received.

Conceptually:

```text
AW handshake
     |
     v
store address

W handshake
     |
     v
store data + strobe

when required information is available
     |
     v
start APB write
```

This is a major RTL design point.

---

# 9. AXI Write Response

After the APB write completes, the bridge must return a response through the AXI B channel.

Important signals:

```text
BVALID
BREADY
BRESP
```

The handshake is:

```text
BVALID && BREADY
```

The bridge must not discard a response merely because:

```text
BREADY = 0
```

The response remains pending until the AXI master accepts it.

---

# 10. AXI Read Transaction

AXI reads use:

```text
AR
```

for the address and:

```text
R
```

for the response.

Example:

```text
ARADDR  = 0x00000020
ARVALID = 1
ARREADY = 1
```

The bridge captures the address and starts an APB read.

After APB completes:

```text
PRDATA
PSLVERR
```

are converted into:

```text
RDATA
RRESP
```

and the bridge asserts:

```text
RVALID
```

The response remains valid until:

```text
RVALID && RREADY
```

occurs.

---

# 11. APB4

APB is a simple peripheral-oriented bus protocol.

An APB transaction consists primarily of two phases:

```text
SETUP
  |
  v
ACCESS
```

APB is intentionally simpler than AXI.

Important APB signals include:

| Signal    | Purpose                 |
| --------- | ----------------------- |
| `PADDR`   | Peripheral address      |
| `PWDATA`  | Write data              |
| `PWRITE`  | Read/write direction    |
| `PSTRB`   | Write byte strobes      |
| `PSEL`    | Peripheral select       |
| `PENABLE` | ACCESS phase indication |
| `PREADY`  | Transfer completion     |
| `PRDATA`  | Read data               |
| `PSLVERR` | Error indication        |

---

# 12. APB SETUP Phase

During SETUP:

```text
PSEL    = 1
PENABLE = 0
```

The bridge presents the transaction information:

```text
PADDR
PWRITE
PWDATA
PSTRB
```

Example:

```text
PSEL    = 1
PENABLE = 0
PADDR   = 0x10
PWRITE  = 1
PWDATA  = 0xDEADBEEF
PSTRB   = 4'b1111
```

This is the APB SETUP phase.

---

# 13. APB ACCESS Phase

The next phase is ACCESS:

```text
PSEL    = 1
PENABLE = 1
```

Example:

```text
PSEL    = 1
PENABLE = 1
PWRITE  = 1
PADDR   = 0x10
PWDATA  = 0xDEADBEEF
```

The bridge then waits for:

```text
PREADY = 1
```

---

# 14. APB Wait States

One of the important jobs of the bridge is handling APB wait states.

For example:

```text
Cycle 1
--------
PSEL    = 1
PENABLE = 0

SETUP
```

```text
Cycle 2
--------
PSEL    = 1
PENABLE = 1
PREADY  = 0

ACCESS / WAIT
```

```text
Cycle 3
--------
PSEL    = 1
PENABLE = 1
PREADY  = 0

ACCESS / WAIT
```

```text
Cycle 4
--------
PSEL    = 1
PENABLE = 1
PREADY  = 1

TRANSFER COMPLETE
```

The bridge must remain in ACCESS while:

```text
PREADY = 0
```

This is an important corner case for verification.

---

# 15. APB Read

For an APB read:

```text
PWRITE = 0
```

The peripheral eventually provides:

```text
PRDATA
```

When:

```text
PREADY = 1
```

the bridge captures the result.

Example:

```text
PADDR   = 0x20
PWRITE  = 0
PRDATA  = 0x12345678
PREADY  = 1
PSLVERR = 0
```

The bridge converts this to the AXI read response:

```text
RDATA = 0x12345678
RRESP = OKAY
```

---

# 16. APB Write

For an APB write:

```text
PWRITE = 1
```

The bridge supplies:

```text
PADDR
PWDATA
PSTRB
```

Example:

```text
PADDR  = 0x10
PWDATA = 0xA5A5A5A5
PSTRB  = 4'b1111
```

The peripheral completes the operation through:

```text
PREADY
```

---

# 17. AXI-to-APB Signal Mapping

The bridge performs logical signal conversion.

A simplified mapping is:

| AXI4-Lite           | APB4               |
| ------------------- | ------------------ |
| `AWADDR` / `ARADDR` | `PADDR`            |
| `WDATA`             | `PWDATA`           |
| write transaction   | `PWRITE = 1`       |
| read transaction    | `PWRITE = 0`       |
| `WSTRB`             | `PSTRB`            |
| APB completion      | `PREADY`           |
| `PRDATA`            | `RDATA`            |
| `PSLVERR`           | AXI response error |

The exact RTL implementation determines how these signals are registered and controlled.

---

# 18. WSTRB and PSTRB

For a 32-bit data bus:

```text
32 bits = 4 bytes
```

Therefore four byte lanes exist.

AXI:

```text
WSTRB[3:0]
```

APB4:

```text
PSTRB[3:0]
```

Conceptually:

```text
WSTRB -> PSTRB
```

Example:

```text
WDATA = 32'h11223344
WSTRB = 4'b1111
```

means all four byte lanes are enabled.

Another example:

```text
WSTRB = 4'b0001
```

enables only one byte lane.

The verification environment should exercise multiple strobe patterns when the implementation supports them.

---

# 19. APB Error Handling

APB can report an error through:

```text
PSLVERR
```

For example:

```text
PREADY  = 1
PSLVERR = 1
```

The bridge must translate this into the appropriate AXI error response.

Conceptually:

```text
PSLVERR = 0
        |
        v
AXI success response

PSLVERR = 1
        |
        v
AXI error response
```

This prevents an APB failure from being incorrectly reported as a successful AXI transaction.

---

# 20. Bridge FSM

The bridge naturally requires a finite state machine because a transaction takes multiple clock cycles.

A conceptual FSM is:

```text
             +------+
             | IDLE |
             +--+---+
                |
                | request accepted
                v
          +-----------+
          | APB_SETUP |
          +-----+-----+
                |
                v
          +-----------+
          | APB_ACCESS|
          +-----+-----+
                |
          +-----+------+
          |            |
      PREADY=0      PREADY=1
          |            |
          |            v
          |       response
          |            |
          +            v
                    IDLE
```

The final response path depends on whether the transaction was:

```text
WRITE
```

or:

```text
READ
```

---

# 21. Why Request Registers Are Required

AXI and APB do not necessarily complete their work in the same clock.

For example:

```text
Cycle 1:
AW handshake

Cycle 2:
W handshake

Cycle 3:
APB SETUP

Cycle 4:
APB ACCESS

Cycle 5:
PREADY = 1
```

The AXI address from Cycle 1 cannot simply be assumed to remain available.

Therefore it should be stored.

Conceptually:

```text
AXI input
   |
   v
register
   |
   v
FSM
   |
   v
APB output
```

This pattern is common in real RTL interfaces.

---

# 22. RTL Design Structure

The bridge RTL can conceptually be divided into:

```text
1. AXI request capture
2. Request state tracking
3. FSM
4. APB output control
5. APB response capture
6. AXI response generation
7. Reset logic
```

A clean implementation separates:

```text
sequential state/register logic
```

from:

```text
combinational next-state/output logic
```

---

# 23. SystemVerilog RTL

This project uses SystemVerilog-oriented RTL constructs such as:

```systemverilog
logic
always_ff
always_comb
typedef enum
parameter
```

Sequential logic example:

```systemverilog
always_ff @(posedge clk) begin

    if (reset) begin
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end

end
```

Combinational logic example:

```systemverilog
always_comb begin

    next_state = state;

    case (state)

        IDLE:
            begin
                // request detection
            end

        APB_SETUP:
            begin
                // move toward ACCESS
            end

        APB_ACCESS:
            begin
                // wait for PREADY
            end

        default:
            begin
                next_state = IDLE;
            end

    endcase

end
```

The exact coding style should always follow the actual RTL in this repository.

---

# 24. Why `always_ff`?

`always_ff` clearly communicates that a block represents sequential logic.

Use it for things such as:

```text
FSM state
address registers
data registers
response registers
transaction flags
```

---

# 25. Why `always_comb`?

`always_comb` is appropriate for combinational decisions such as:

```text
next_state
APB control signals
decode logic
ready logic
```

Provide complete assignments so unintended latch inference is avoided.

A safe pattern is:

```systemverilog
always_comb begin

    next_state = state;

    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;

    ...
end
```

---

# 26. Verification Architecture

The verification environment follows:

```text
                SystemVerilog Testbench
                         |
              +----------+----------+
              |                     |
              v                     v
        AXI Stimulus          APB Peripheral
              |                     Model
              |                     |
              +----------+----------+
                         |
                         v
                       DUT
                         |
                         v
                      Checks
                         |
                    PASS / FAIL
```

The testbench should not simply generate signals.

It should determine whether the DUT behaves correctly.

---

# 27. Self-Checking Verification

A self-checking testbench compares:

```text
EXPECTED
   vs
ACTUAL
```

Example:

```systemverilog
if (actual_data !== expected_data) begin

    $error(
        "[FAIL] expected=%h actual=%h",
        expected_data,
        actual_data
    );

end
```

When they match:

```text
[PASS]
```

This is much stronger than manually looking at every waveform.

---

# 28. AXI Write Test

Example test:

```text
Address = 0x00000010
Data    = 0xDEADBEEF
WSTRB   = 1111
```

The testbench should verify:

```text
AW handshake
W handshake
APB PADDR
APB PWRITE
APB PWDATA
APB PSTRB
APB completion
BVALID
BRESP
```

---

# 29. AXI Read Test

Example:

```text
Address = 0x00000020
APB PRDATA = 0x12345678
```

Check:

```text
AR handshake
APB PADDR
PWRITE = 0
PREADY
PRDATA
RDATA
RRESP
RVALID
```

---

# 30. AW/W Ordering Tests

These tests are particularly important.

### Test A — AW and W together

```text
AWVALID = 1
WVALID  = 1
```

### Test B — AW first

```text
Cycle 1:
AW handshake

Cycle 2:
W handshake
```

### Test C — W first

```text
Cycle 1:
W handshake

Cycle 2:
AW handshake
```

The bridge should preserve the complete transaction information.

---

# 31. APB Wait-State Test

The APB peripheral model can deliberately hold:

```text
PREADY = 0
```

for multiple cycles.

Example:

```text
SETUP
   |
   v
ACCESS / PREADY=0
   |
   v
ACCESS / PREADY=0
   |
   v
ACCESS / PREADY=1
```

Check that the bridge does not terminate ACCESS early.

---

# 32. APB Error Test

Force:

```text
PSLVERR = 1
```

during a completed APB transfer.

Verify that the AXI response is an error response.

This test is important because it validates actual protocol conversion rather than only successful traffic.

---

# 33. AXI Response Backpressure

Test:

```text
BVALID = 1
BREADY = 0
```

The response must remain pending.

Likewise:

```text
RVALID = 1
RREADY = 0
```

must not cause the read response to disappear.

The general rule is:

```text
VALID remains asserted until handshake.
```

---

# 34. Reset Test

Reset should return the bridge to a known state.

Typical expectations:

```text
FSM -> IDLE
AXI response VALID -> inactive
APB PSEL -> inactive
APB PENABLE -> inactive
pending requests -> cleared
```

The exact reset polarity and implementation should match the RTL.

---

# 35. Corner Cases

Important corner cases include:

```text
AW arrives before W
W arrives before AW
AW and W arrive together
APB PREADY delayed
APB PSLVERR asserted
BREADY delayed
RREADY delayed
Back-to-back write transactions
Back-to-back read transactions
Read after write
Write after read
Different write strobes
Reset between transactions
```

The purpose is to verify behavior at protocol boundaries, not just the simplest successful path.

---

# 36. Waveform Analysis

GTKWave can be used to inspect the actual timing of the transaction.

For an AXI write inspect:

```text
AWVALID
AWREADY
AWADDR

WVALID
WREADY
WDATA
WSTRB

BVALID
BREADY
BRESP
```

For APB inspect:

```text
PSEL
PENABLE
PADDR
PWRITE
PWDATA
PSTRB
PREADY
PRDATA
PSLVERR
```

---

# 37. What a Correct APB Waveform Should Show

For a normal APB transfer:

```text
          SETUP            ACCESS

PSEL       1                 1
PENABLE    0                 1
PADDR      valid             valid
PWRITE     valid             valid
PWDATA     valid             valid
PREADY                       1
```

For a wait-state transfer:

```text
          SETUP       ACCESS       ACCESS       ACCESS

PSEL        1           1            1            1
PENABLE     0           1            1            1
PREADY                  0            0            1
```

The bridge must remain in ACCESS until completion.

---

# 38. Debugging Method

When a test fails, do not inspect the entire waveform randomly.

Follow the transaction from left to right:

```text
1. Did AXI request arrive?
2. Did VALID/READY handshake?
3. Was the request captured?
4. Did the FSM change state?
5. Did APB SETUP occur?
6. Did APB ACCESS occur?
7. Did PREADY arrive?
8. Was PRDATA/PSLVERR captured?
9. Was the correct AXI response generated?
10. Did the response handshake?
```

Find the **first point where the behavior becomes incorrect**.

That is usually much faster than starting with the final error.

---

# 39. Common RTL Mistakes

### Mistake 1 — Assuming AW and W arrive together

This breaks the independent-channel nature of AXI.

### Mistake 2 — Losing the captured address

Using a live AXI address after the request has already been accepted can produce incorrect APB transactions.

### Mistake 3 — Leaving ACCESS when PREADY is low

If:

```text
PREADY = 0
```

the bridge should keep the APB transfer active.

### Mistake 4 — Dropping BVALID/RVALID too early

The AXI response must remain available until accepted.

### Mistake 5 — Ignoring PSLVERR

An APB error must not become an AXI success response.

### Mistake 6 — Incorrect strobe handling

Byte-lane information must be transferred consistently.

### Mistake 7 — Stale request state after reset

Transaction flags and stored request information should be reset appropriately.

---

# 40. Simulation

The project is intended to be simulated using the RTL tools used during development.

Typical Icarus Verilog compilation:

```bash
iverilog -g2012 \
    -o sim/axi_apb_bridge_sim \
    rtl/axi_apb_bridge.sv \
    tb/axi_apb_bridge_tb.sv
```

Run:

```bash
vvp sim/axi_apb_bridge_sim
```

If the testbench generates a VCD:

```bash
GDK_BACKEND=x11 gtkwave sim/<waveform>.vcd
```

The exact file names should match the final repository contents.

---

# 41. Verification Results

Final results should be recorded from the actual simulation.

| Verification Area     | Result        |
| --------------------- | ------------- |
| Reset                 | To be updated |
| AXI Write             | To be updated |
| AXI Read              | To be updated |
| AW/W ordering         | To be updated |
| APB SETUP             | To be updated |
| APB ACCESS            | To be updated |
| APB wait states       | To be updated |
| APB error             | To be updated |
| AXI response handling | To be updated |
| Strobe handling       | To be updated |
| Corner cases          | To be updated |
| Final regression      | To be updated |

**The final result will only be marked PASS after the current RTL and testbench are executed together.**

---

# 42. Project Files

Recommended repository organization:

```text
AXI4_Lite_APB4_Bridge/
│
├── README.md
│
├── rtl/
│   └── axi_apb_bridge.sv
│
├── tb/
│   └── axi_apb_bridge_tb.sv
│
├── sim/
│   └── waveform files
│
├── docs/
│   └── study material
│
└── results/
    └── test results
```

The exact file names should follow the source files uploaded to the repository.

---

# 43. Skills Demonstrated

This project demonstrates practical work with:

```text
SystemVerilog
RTL Design
Finite State Machines
Sequential Logic
Combinational Logic
AXI4-Lite
APB4
VALID/READY Handshaking
Memory-Mapped Interfaces
Protocol Conversion
Request Capture
Response Handling
Byte Strobes
Wait-State Handling
Error Propagation
Self-Checking Testbenches
Waveform Debugging
Icarus Verilog
GTKWave
```

---

# 44. Interview Explanation

A concise explanation of the project:

> I designed an AXI4-Lite to APB4 bridge in SystemVerilog. The bridge accepts AXI4-Lite read and write transactions, captures the required request information, converts the transaction into the APB4 SETUP and ACCESS phases, waits for APB completion through PREADY, and then generates the corresponding AXI response. I also developed a SystemVerilog verification environment to test normal transactions, independent AXI write-channel timing, APB wait states, APB errors, response backpressure, and corner cases, using waveform analysis to debug transaction-level behavior.

This explanation should be adjusted to exactly match the final RTL and verification environment.

---

# 45. Why This Project Matters for RTL Design

The project combines several important RTL concepts:

```text
           Protocol
              |
              v
        +-----------+
        |    FSM    |
        +-----------+
              |
              v
       State Registers
              |
              v
       Signal Translation
              |
              v
        APB Transaction
              |
              v
        AXI Response
```

The main learning is not simply how to memorize AXI or APB signals.

It is understanding how to design hardware that:

```text
accepts a request
      ->
remembers it
      ->
executes it using another protocol
      ->
waits for completion
      ->
returns the result
```

---

# 46. Relationship to Other RTL Projects

This project demonstrates a different class of RTL skill from a synchronous FIFO.

### Parameterized FIFO

```text
data storage
     |
     v
pointers
     |
     v
count
     |
     v
full / empty
```

Focus:

```text
core sequential RTL
boundary conditions
parameterization
data movement
```

### AXI4-Lite → APB4 Bridge

```text
AXI
 |
 v
handshake
 |
 v
FSM
 |
 v
APB
 |
 v
response
```

Focus:

```text
protocol RTL
FSM control
transaction tracking
interface conversion
verification
```

Together they demonstrate both core RTL design and interface/protocol RTL.

---

# 47. Scope

This project intentionally focuses on:

```text
AXI4-Lite
APB4
SystemVerilog RTL
Protocol conversion
Self-checking verification
Simulation
Waveform debugging
```

It does not attempt to implement every feature of full AXI4.

In particular, AXI4-Lite is being used for single-beat register-style transactions.

Possible advanced extensions are listed separately as future work.

---

# 48. Future Improvements

Potential future improvements include:

```text
Constrained-random verification
SystemVerilog assertions
Functional coverage
Formal verification
More extensive APB peripheral modeling
More comprehensive protocol checking
Configurable address/data widths
Additional corner-case scenarios
Reusable verification components
UVM-based verification
```

These are future improvements and are not automatically claims about the current implementation.

---

# 49. Final Mental Model

Remember the project as:

```text
                         AXI4-Lite
                            |
                            v
                     +-------------+
                     |   CAPTURE   |
                     +------+------+
                            |
                            v
                         AXI FSM
                            |
                            v
                       APB SETUP
                            |
                            v
                      APB ACCESS
                            |
                   +--------+--------+
                   |                 |
               PREADY=0          PREADY=1
                   |                 |
                   +-----> wait      |
                                     v
                              APB response
                                     |
                                     v
                              AXI response
                                     |
                                     v
                                  IDLE
```

The entire bridge can be remembered using four words:

```text
CAPTURE
TRANSLATE
WAIT
RESPOND
```

---

# 50. Final Checklist

Before declaring the project complete:

```text
[ ] RTL compiles
[ ] Testbench compiles
[ ] Reset verified
[ ] AXI write verified
[ ] AXI read verified
[ ] AW/W independent timing verified
[ ] APB SETUP verified
[ ] APB ACCESS verified
[ ] PREADY wait states verified
[ ] PSLVERR verified
[ ] B response verified
[ ] R response verified
[ ] Response backpressure verified
[ ] WSTRB/PSTRB verified
[ ] Corner cases verified
[ ] Waveform inspected
[ ] Final simulation result recorded
[ ] README updated to match actual implementation
[ ] Temporary files removed
```

---

## Project Philosophy

This repository is intended to show **understanding rather than code volume**.

The most important goal is not to make the project look large.

The goal is to be able to open the RTL and explain:

```text
WHY is this register here?
WHY is this state required?
WHY does AXI need this handshake?
WHY does APB need SETUP and ACCESS?
WHAT happens when PREADY is low?
WHAT happens when AW and W arrive separately?
HOW is an APB error returned to AXI?
HOW does the testbench prove the behavior?
```

If those questions can be answered from the RTL, testbench, and waveform, the project becomes a meaningful RTL design and verification exercise.
