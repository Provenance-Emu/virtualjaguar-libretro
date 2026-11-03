# Upstream issue drafts

Paste-ready issue text for problems found in this repo that belong
**upstream**. Each entry states the measured behaviour, the exact
reproduction, and the source location, so a maintainer can act on it
without re-deriving anything.

Two upstreams are involved:

| # | upstream | repo | what it is |
|---|----------|------|------------|
| 1 | `libretro/virtualjaguar-libretro` | this repo's `src/` | a core behaviour gap |
| 2 | `mwenge/rmac` | the Jaguar assembler | a toolchain defect |

Both surviving drafts have been filed:

| draft | filed as |
|---|---|
| cart HLE user stack pointer | https://github.com/libretro/virtualjaguar-libretro/issues/1165 (as a question: the behaviour is measured, the BIOS fidelity is not) |
| `cmp #imm,Dn` -> illegal CMP | https://github.com/mwenge/rmac/issues/2 |

Issue 3 of an earlier revision (the OP DWIDTH/PITCH claim) was withdrawn
before filing — see "Claims that did not reproduce".

**Every reproduction below was re-run against a pristine build** of the
pinned toolchain (`tools/jaguar-toolchain/PIN`: rmac `50e66ea`, rln
`a617009`) with `make clean` before the build. An earlier draft of Issue 2
claimed two defects that do **not** reproduce; they are listed at the end
of this file under "Claims that did not reproduce", with the reason each
one was wrong, so nobody files them again.

---

## Issue 1 — the cart HLE boot path never initialises the 68000's user stack pointer

**Upstream:** https://github.com/libretro/virtualjaguar-libretro
**Suggested title:** `cart HLE boot leaves the 68000's user stack pointer at 0 — the standard drop-to-user-mode idiom then faults the CPU`

### Summary

A cartridge booted through the HLE path gets a valid *supervisor* stack
pointer but no *user* stack pointer. The standard "drop to user mode"
idiom

```asm
        move.w  #$0700,sr
```

therefore swaps A7 with a user stack pointer that was never initialised,
installing **A7 = 0**. On a 68000 `MOVESR` is a privileged instruction, so
user-mode code cannot undo the swap with another `MOVE.W #imm,SR` — the
program is stuck with a zero stack pointer, and the first `JSR` pushes
its return address to `$FFFFFFFC`, from which the `RTS` pops `$FFFFFFFF`
and the CPU faults to PC 0.

### Measured

From the probe ROM in `test/microbench/benchdemo_stackprobe.s` (values
read from main RAM `$010000`+ by `test/tools/probe_demo_sentinels.c`):

| sentinel | value | meaning |
|----------|-------|---------|
| `$010014` | `00004000` | A7 at entry — the HLE SSP, **correct** |
| `$010018` | `00000000` | A7 after `move.w #$0700,sr` — **zero** |
| `$01001C` | `00C0DE00` | the subroutine was reached (its absolute store worked) |
| `$010020` | `FFFFFFFF` | `(sp)` in user mode — the push landed at `$FFFFFFFC`, unmapped |
| `$010004` | `00000000` | the DONE sentinel was never written — the ROM died |

### Reproduction

```bash
# build the probe ROM
cd test/microbench
T=../../tools/vendor/jaguar-toolchain
$T/rmac/rmac -fb -o /tmp/sp.o benchdemo_stackprobe.s
$T/rln/rln -n -a 800000 x x -o benchdemo_stackprobe.j64 /tmp/sp.o

# build and run the sentinel dumper (from the repository root)
cd ../..
cc -O2 -Wall -std=c99 -o /tmp/probe_sents \
   test/tools/probe_demo_sentinels.c test/harness/harness.c -ldl -lm
/tmp/probe_sents ./virtualjaguar_libretro.so \
   test/microbench/benchdemo_stackprobe.j64 --frames 20
```

`test/microbench/benchdemo_stacktest.j64` is the same program with one
line added — `move.l #$00003FF0,a7` right after the transition — and it
reaches its DONE sentinel (`$C0DE0068`) instead of dying. That is the
workaround, and it is what every ROM in `test/microbench/` has to do.

### Where it comes from

* `src/m68000/m68kinterface.c:456` — `m68k_pulse_reset()` loads the
  supervisor stack pointer into A7 and forces `regs.s = 1`:

  ```c
  regs.intmask = 0x07;
  regs.s = 1;                                   // Supervisor mode ON
  m68k_areg(regs, 7) = m68k_read_memory_32(0);  // the SSP
  m68k_setpc(m68k_read_memory_32(4));           // the entry PC
  ```

  It never writes `regs.usp` or `regs.isp`. Both are 0 from power-on
  (the `regs` struct is a global) and stay 0 until software writes them.

* `src/m68000/cpuextra.c:53` — `MakeFromSR()` implements a privilege
  change as an A7 ↔ `regs.usp` swap, so the first transition to user mode
  installs the never-initialised `regs.usp` as the live stack pointer.

* `src/core/jaguar.c:1529-1536` — the HLE cart boot writes the SSP to
  main RAM `$0000` (`HLE_SSP_CART` = `$4000`) and the entry PC to
  `$0004`, then `JaguarReset()` pulses the CPU reset at
  `src/core/jaguar.c:1683`.

### Why this is a core gap and not just "the BIOS's job"

The HLE cart path **replaces** the boot ROM's code, so it has to
reproduce the register state the BIOS would have left behind. The core
already reproduces a list of other BIOS leftovers in the same function:

* the BIOS workspace flag at `$0804` (`HLE_BIOS_WORK_FLAG_ADDR`),
* the GPU auth magic (`GPU_AUTH_MAGIC`),
* the OP STOP list,
* the MEMCON1 cart bus-width bits,
* the exception vectors and the `RTE` stubs at `$400`/`$404`.

The 68000's user stack pointer is the one BIOS leftover in that list that
is missing. The supervisor stack pointer is provided; the user one is
not, and there is no way for a cart to recover: `MOVESR` is privileged,
so a program that has already dropped to user mode cannot return to
supervisor mode to fix A7 — the only way back is `RTE` from an
exception handler, which itself needs a working stack.

### Suggested fix

Initialise `regs.usp` in `m68k_pulse_reset()` to a valid user stack, and
keep `regs.isp` in step with the SSP that was just loaded, e.g.:

```c
regs.intmask = 0x07;
regs.s = 1;                                   // Supervisor mode ON
m68k_areg(regs, 7) = m68k_read_memory_32(0);  // the SSP
regs.isp = m68k_areg(regs, 7);                // keep it in the SSP slot
regs.usp = <a valid user stack>;
m68k_setpc(m68k_read_memory_32(4));
```

The question left open is *which* address the user stack should be. The
three candidates are the same value as the SSP (`$4000`, i.e. the user
and supervisor stacks alias, which is what a lot of 68000 code assumes),
the top of main RAM (`$200000`, which is what the CD path already uses
for its SSP — `src/cd/jagcd_hle.c:1946`), or the value the real boot ROM
leaves behind. Any of them is better than 0, because 0 makes the first
`JSR` in user mode write to `$FFFFFFFC`.

Note that `src/cd/jagcd_hle.c` sets the SSP explicitly
(`m68k_set_reg(M68K_REG_SP, 0x00200000)`) but likewise leaves `regs.usp`
alone, so the CD path has the same gap.

### Open question for the maintainer

Does the real Jaguar boot ROM leave a usable user stack pointer behind
when it hands control to the cart? If it leaves 0 as well, then the
faithful fix is to document "a cart must set up its own user stack
before dropping to user mode" rather than to invent a value — but the
HLE path should then say so somewhere a cart author would find it,
because the failure mode (a silent zero stack pointer) is not something
you can debug from the outside.

---

## Issue 2 — `cmp.w #imm,Dn` is encoded as a CMP with an immediate effective address, which is an illegal instruction

**Upstream:** https://github.com/mwenge/rmac (pinned at `50e66ea`; see
`tools/jaguar-toolchain/PIN`)
**Suggested title:** `cmp.w #imm,Dn` assembles to a CMP with an immediate EA (an illegal instruction) instead of CMPI

### Summary

`cmp.w #5,d0` assembles to

```
B0 7C 00 05
```

`B0 7C` is `CMP.W` with **mode 7 / register 4 (immediate)** in the source
effective-address field. `CMP <ea>,Dn` has no immediate form on the
68000 — that is what the separate `CMPI` instruction is for — so the
encoding is not a legal instruction. The intended bytes are

```
CMPI.W #5,D0   =   0C 40 00 05
```

which is what other 68000 assemblers emit for this source form.

This matters because it is *silent*: `rmac` reports no diagnostic and
`rln` links the object. Emulators whose EA decoder is generic enough will
happily execute `B0 7C` (this repo's core does, which is how the encoding
was noticed — the result looked right and the bytes were wrong), so the
mistake can survive until the code meets a 68000, where it takes the
illegal-instruction exception (vector 4) instead of comparing.

### Reproduction

The evidence is the byte pattern; no emulator is needed.

```bash
T=tools/vendor/jaguar-toolchain
printf '        .68000\n        .text\nstart:\n        cmp.w   #5,d0\n' > /tmp/cmp.s
$T/rmac/rmac -fb -o /tmp/cmp.o /tmp/cmp.s
xxd -s 0x20 -l 4 /tmp/cmp.o      # b07c 0005
```

| source | rmac | correct |
|---|---|---|
| `cmp.w #5,d0` | `B0 7C 00 05` (CMP, immediate EA) | `0C 40 00 05` (CMPI.W) |
| `cmp.l #5,d0` | `B0 BC 00 00 00 05` | `0C 80 00 00 00 05` |
| `cmp.b #5,d0` | `B0 3C 00 05` | `0C 00 00 05` |

### Suggested fix

Encode `cmp.{b,w,l} #imm,Dn` as `CMPI` (the natural reading of the
source, and what every other 68000 assembler does), or reject the form
with a diagnostic. Silently emitting an EA mode the instruction does not
support is the one option that produces code which assembles, links and
then does something else.

---

## Claims that did not reproduce

Kept here so they are not filed again, with the reason each was wrong.

* **"rmac mis-encodes `SUB.L` with a non-D0 source register (the source
  register one bit low, so `sub.l d3,d2` subtracts D1)."** — Not an rmac
  bug. rmac assembles `sub.l d3,d2` as `94 83` (`SUB.L D3,D2`), which is
  correct; the core executes it correctly too (`sub.l d3,d2` with D3=5,
  D2=10 gives 5). The bad result in the original probe came from the
  probe ROM itself: its header's entry vector was `$00802008` while the
  code starts at `$00802000`, so the CPU started *inside* the first
  instruction and never executed `move.l #5,d3` — the "SUB is broken"
  observation was the ROM skipping its own setup. The probe ROMs in
  `test/microbench/` now have their entry vectors checked against the
  label they are supposed to reach.
* **"A file with a forward immediate and a forward conditional branch
  makes rmac abort with `Error: undefined expression`."** — The
  reproduction used two labels that differ only in case (`bne.s later`
  against a label named `LATER:`). rmac's symbols are case-sensitive
  (see the "Symbols and Scope" section of its manual), so the branch
  referenced an undefined symbol and the error was correct. With
  matching names the same file assembles and links cleanly.
* **"`move.l Dn,<absolute>` is assembled backwards."** — Not an rmac
  bug: `move.l d0,$00100000` assembles as `23 C0 00 10 00 00`
  (`MOVE.L D0,(xxx).L`), which is correct. The workaround the earlier
  session used (`move.l #ADDR,aN` + `move.l d0,(aN)`) is still
  convenient, but nothing is mis-assembled.
* **"`LEA`/`MOVE` with a displacement are mis-assembled."** — A plain
  displacement (`4(a0)`) assembles correctly (`32 28 00 04`). What is
  broken is a **label** in an indexed form (Issue 2 above), because the
  label becomes a section-relative displacement.
* **"The OP decodes DWIDTH together with PITCH, so every bitmap is
  sheared by a byte per line."** — Withdrawn before filing. `0xFFC0000`
  is `0x3FF << 18`, i.e. bits 18-27, which is the whole ten-bit DWIDTH
  field (JTRM Rev 8 p.20); it does not reach down to PITCH (bits
  15-17), and `>>15` is exactly the `*8` that turns phrases into bytes.
  The decode was correct. A control settled it: with either mask the
  demo's 80-phrase line gives 640 bytes, so the demo frames and both
  committed regression ROMs are pixel-identical under the "old" and the
  "fixed" build (0 differing pixels of 78240, 78566 and 104594). The
  commit that changed the mask to `0x3FC0000` truncated DWIDTH to eight
  bits and was dropped.

* **"`move.w TBL(a0),d1` is assembled with a section-relative
  displacement instead of the label's address."** — Withdrawn. rmac
  emits the label's **absolute address truncated to 16 bits**, which is
  the standard behaviour of every 68000 assembler for a form the
  instruction cannot represent (there is no absolute-indexed MOVE).
  Measured with the same source linked at two bases: at `$800000` the
  displacement is `0003`, at `$800004` it is `0007` — i.e. the low 16
  bits of `$800003`/`$800007`, not an offset from the section base.
  The read lands in the wrong place because the base is dropped, but
  that is inherent to `d16(An)`; a diagnostic would be a fair request,
  a mis-assembly bug it is not.
* **"`move.w 0(a1,a0),d2` loses the index scale, so the index is always
  byte-scaled."** — Withdrawn, and it is not a defect: on the 68000 the
  scale is an explicit part of the syntax, and `0(a1,a0)` means scale
  x1. rmac encodes the scale correctly when it is written —
  `0(a1,a0.w*2)` gives `34 31 82 00` (scale 01) and `0(a1,a0.l*4)`
  gives `24 31 8C 00` (scale 10). The `$2222` the old probe read was
  `TBL+2`, which is exactly what `x1` should give with an index of 2.
