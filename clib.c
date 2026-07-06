// Foreign caller, compiled with -O2 so the five live pointers stay in
// callee-saved registers (rbx, r12-r15, rbp) across the callback call — exactly
// what optimized Rust (e.g. wgpu-native) does. The System V AMD64 ABI requires a
// #c_call callback to preserve those registers. If it doesn't, one of p1..p5 is
// corrupted after the callback returns and the frees below crash.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef void (*Callback)(uint32_t status, void* userdata1, void* userdata2);

void fireCallback(Callback callback, void* userdata1) {
    void* p1 = malloc(32);
    void* p2 = malloc(64);
    void* p3 = malloc(128);
    void* p4 = malloc(256);
    void* p5 = malloc(512);
    callback(1, userdata1, (void*)0);
    printf("C: after callback: %p %p %p %p %p\n", p1, p2, p3, p4, p5);
    free(p1); free(p2); free(p3); free(p4); free(p5);
    printf("C: survived frees\n");
}
