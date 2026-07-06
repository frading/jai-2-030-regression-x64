// Larger-frame reproduction (extra locals + a little String_Builder work, like a
// real callback). This frame shape (0x23a0) is the REGRESSION SURFACE:
//
//     0.2.029  -x64  => "C: survived frees"        (correct)
//     0.2.030  -x64  => double free / Aborted       (miscompiled)
//     any      -llvm => "C: survived frees"         (correct)
//
// Between 0.2.029 and 0.2.030 the callee-saved-register save area shifted up by 8
// bytes while the rax spill slot stayed put, moving the r15 save onto the rax
// spill slot. That is how the (already-present) bug started hitting real code.
// See README.md for the annotated disassembly.

#import "Basic";

clib :: #library,no_dll "clib";
fireCallback :: (callback: (status: u32, userdata1: *void, userdata2: *void) #c_call, userdata1: *void) #foreign clib;

state: [8] float;

_onCallback :: (status: u32, userdata1: *void, userdata2: *void) #c_call {
    c: #Context;
    push_context c {
        if status != 1  return;
        for slotIndex: 0..7  state[slotIndex] = (cast(float) slotIndex) * 3.25 + 5.0;
        builder: String_Builder;
        append(*builder, "cb:");
        for slotIndex: 0..7  print_to_builder(*builder, " %", state[slotIndex]);
        text := builder_to_string(*builder,, temp);
        print("JAI: %\n", text);
    }
}

main :: () {
    fireCallback(_onCallback, null);
    print("JAI: done\n");
}
