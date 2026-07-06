This is a minimal repro for a regression in jai 2.030 where calling into a DLL can lead to crash when compiling with x64.

Tested on linux (PopOS)

# 1. Build dll

`gcc -O2 -c clib.c -o clib.o && ar rcs clib.a clib.o`

# 2. Compile and run with jai

## jai 2.029 (all 4 cases run successfully, with x64/llvm and example repro_minimal/repro_larger_frame)

`export PATH=<path-to-jai-2.029-bin-folder>:$PATH`

`jai repro_minimal.jai -x64 && ./repro_minimal`            # -> C: survived frees
`jai repro_minimal.jai -llvm && ./repro_minimal`           # -> C: survived frees
`jai repro_larger_frame.jai -x64 && ./repro_larger_frame`  # -> C: survived frees
`jai repro_larger_frame.jai -llvm && ./repro_larger_frame` # -> C: survived frees

## jai 2.030 (binary compiled with x64 crashes)

`export PATH=<path-to-jai-2.030-bin-folder>:$PATH`

`jai repro_minimal.jai -x64 && ./repro_minimal`            # -> crash with free(): double free detected in tcache 2
`jai repro_minimal.jai -llvm && ./repro_minimal`           # -> C: survived frees
`jai repro_larger_frame.jai -x64 && ./repro_larger_frame`  # -> free(): double free detected in tcache 2
`jai repro_larger_frame.jai -llvm && ./repro_larger_frame` # -> C: survived frees
