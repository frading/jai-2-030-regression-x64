// Minimal reproduction: a #c_call callback that declares a #Context and does
// push_context (with an EMPTY body) corrupts the caller's r15.
//
// Build & run (x64 backend — the bug):
//     gcc -O2 -c clib.c -o clib.o && ar rcs clib.a clib.o
//     jai repro_minimal.jai -x64 && ./repro_minimal
//   => "free(): double free detected in tcache 2" / Aborted
//
// With the LLVM backend it is correct:
//     jai repro_minimal.jai -llvm && ./repro_minimal   => "C: survived frees"
//
// This frame shape (0x1120) collides on BOTH 0.2.029 and 0.2.030.

#import "Basic";

clib :: #library,no_dll "clib";
fireCallback :: (callback: (status: u32, userdata1: *void, userdata2: *void) #c_call, userdata1: *void) #foreign clib;

_onCallback :: (status: u32, userdata1: *void, userdata2: *void) #c_call {
    c: #Context;
    push_context c {
    }
}

main :: () {
    fireCallback(_onCallback, null);
    print("JAI: done\n");
}
