# x64 backend: `#c_call` + `push_context` corrupts the caller's callee-saved `r15`

**Compiler:** Jai beta 0.2.030 (and 0.2.029 — see below)
**Platform:** Linux x86_64, **x64 backend only**. The LLVM backend is correct at every optimization level.
**Severity:** silent ABI violation → memory corruption in the *caller*. For us it manifested as a heap crash inside a Rust library (wgpu-native) on the first rendered frame.

---

## TL;DR

A `#c_call` procedure that declares a `#Context` and does `push_context` gets a prologue in which the **saved `r15` is immediately overwritten by an `rax` spill to the same stack slot**. The epilogue then restores that clobbered value into `r15`. Because a `#c_call` procedure must preserve `r15` per the System V AMD64 ABI, any foreign caller that keeps a live value in `r15` across the call (optimized C/Rust — frame-pointer omitted, live pointers in callee-saved registers) is corrupted.

```
sub    $0x1120,%rsp
mov    %rbx,0x10f8(%rsp)
mov    %r12,0x1100(%rsp)
mov    %r13,0x1108(%rsp)
mov    %r14,0x1110(%rsp)
mov    %r15,0x1118(%rsp)      ; r15 saved at 0x1118 ...
mov    %rax,0x1118(%rsp)      ; ... immediately overwritten by the rax spill
...
mov    0x1118(%rsp),%r15      ; epilogue restores the clobbered value into r15
```

The callee-saved save area and a general spill slot overlap by exactly one 8-byte slot (the top one, where `r15` lives).

---

## Reproduce

```
./build_and_run.sh /path/to/jai        # or just: ./build_and_run.sh   (uses `jai` on PATH)
```

Or by hand:

```
gcc -O2 -c clib.c -o clib.o && ar rcs clib.a clib.o
jai repro_minimal.jai -x64 && ./repro_minimal      # => double free / Aborted
jai repro_minimal.jai -llvm && ./repro_minimal     # => "C: survived frees"
```

`clib.c` is the foreign caller (compiled `-O2` so its five `malloc` pointers stay in `rbx/r12-r15/rbp` across the callback, like optimized Rust). `repro_*.jai` is the Jai callback.

### Observed

| repro | frame | 0.2.029 `-x64` | 0.2.030 `-x64` | any `-llvm` |
|-------|-------|----------------|----------------|-------------|
| `repro_minimal` (empty `push_context`) | `0x1120` | **crash** | **crash** | ok |
| `repro_larger_frame` (extra locals + `String_Builder`) | `0x23a0` | ok | **crash** | ok |

(The minimal case's crash is heap-layout sensitive, so an individual run occasionally survives; `build_and_run.sh` runs each binary 20× to make the signal unambiguous. The larger-frame case is deterministic: 0.2.029 always survives, 0.2.030 always crashes.)

The trigger is specifically `push_context`: a callback with no `#Context`, or one that only *declares* `c: #Context;` without pushing it, is **not** affected.

---

## Root cause (annotated disassembly)

The callee-saved save area is laid out ascending (`rbx, r12, r13, r14, r15`), and an `rax` spill slot is allocated at the very top of the frame — **the same offset as the `r15` save**.

### `repro_minimal`, frame `0x1120` — collides on both versions

```
                         0.2.029                         0.2.030
sub    $0x1120,%rsp                        sub    $0x1120,%rsp
mov    %rbx,0x10f8(%rsp)                    mov    %rbx,0x10f8(%rsp)
mov    %r12,0x1100(%rsp)                    mov    %r12,0x1100(%rsp)
mov    %r13,0x1108(%rsp)                    mov    %r13,0x1108(%rsp)
mov    %r14,0x1110(%rsp)                    mov    %r14,0x1110(%rsp)
mov    %r15,0x1118(%rsp)   <-- r15          mov    %r15,0x1118(%rsp)   <-- r15
mov    %rax,0x1118(%rsp)   <-- CLOBBER      mov    %rax,0x1118(%rsp)   <-- CLOBBER
```

### `repro_larger_frame`, frame `0x23a0` — the 0.2.029 → 0.2.030 regression

```
                         0.2.029 (SAFE)                  0.2.030 (BROKEN)
sub    $0x23a0,%rsp                        sub    $0x23a0,%rsp
mov    %rbx,0x2370(%rsp)                    mov    %rbx,0x2378(%rsp)
mov    %r12,0x2378(%rsp)                    mov    %r12,0x2380(%rsp)
mov    %r13,0x2380(%rsp)                    mov    %r13,0x2388(%rsp)
mov    %r14,0x2388(%rsp)                    mov    %r14,0x2390(%rsp)
mov    %r15,0x2390(%rsp)   <-- r15 at 90    mov    %r15,0x2398(%rsp)   <-- r15 at 98
mov    %rax,0x2398(%rsp)   <-- rax at 98    mov    %rax,0x2398(%rsp)   <-- rax at 98
                            (no overlap)                                 (OVERLAP)
```

Between 0.2.029 and 0.2.030 the **entire save area shifted up by 8 bytes** (`rbx` `0x2370`→`0x2378`, … `r15` `0x2390`→`0x2398`) while the `rax` spill slot stayed at `0x2398`. On 0.2.029 the save area ended one slot *below* the spill (safe); on 0.2.030 `r15` lands *on* the spill slot. The bug's generation logic is present in both versions — 0.2.030 merely shifted which frame shapes collide, which is what moved it onto real-world callbacks.

### Why it becomes a double free

In `clib.c` the last thing before `call *callback` is `mov %rax,%rbp` (`rbp = p5 = malloc(512)`), so `rax = p5` at callback entry. The callback overwrites saved `r15` with `rax` = `p5`. `r15` held `p1`, so after the callback `r15 == p5`. The C caller then `free`s `r15` (thinking it is `p1`) and later `free`s `rbp` (`p5`) — **`p5` is freed twice** → `free(): double free detected in tcache 2` (the 512-byte bin).

---

## Real-world impact (how we hit it)

We build our engine's debug configuration with the x64 backend. Our wgpu buffer-map-async callbacks are `#c_call` + `push_context`. On 0.2.029 their frame shapes happened to land one slot clear of the spill; upgrading to 0.2.030 shifted them onto the collision. wgpu-native (Rust, release, frame-pointer omitted) keeps its closure `Box` pointer in a callee-saved register across the callback, so on return that pointer was garbage and wgpu-native crashed in `free()` on the first rendered frame. At a debugger: `r15 = 0x0` at callback entry, `r15 = <spilled rax>` immediately after it returns.

---

## Workaround

Compile the affected translation units with the **LLVM backend** (correct at all optimization levels). The x64 backend is otherwise unaffected for code that doesn't cross a foreign ABI boundary with live values in callee-saved registers.

---

## Files

- `README.md` — this file
- `clib.c` — the foreign (`-O2`) caller
- `repro_minimal.jai` — empty `push_context`; crashes on 0.2.029 and 0.2.030
- `repro_larger_frame.jai` — larger frame; safe on 0.2.029, crashes on 0.2.030
- `build_and_run.sh` — builds each repro with both backends and runs them
