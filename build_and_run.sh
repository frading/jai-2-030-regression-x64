#!/usr/bin/env bash
# Reproduce the x64-backend #c_call+push_context miscompile.
#
# Usage:  ./build_and_run.sh [path-to-jai]
#   path-to-jai defaults to `jai` on PATH.
#
# For each repro it builds with both the x64 and the LLVM backend and runs each
# binary 20 times (the crash is ASLR/heap-layout sensitive for the minimal case,
# so a single run can occasionally survive; 20 runs makes the signal clear).
set -u
JAI="${1:-jai}"
echo "Using compiler: $JAI"
"$JAI" -version || true
echo

gcc -O2 -c clib.c -o clib.o && ar rcs clib.a clib.o || { echo "clib build failed"; exit 1; }

run_many() {
    local bin="$1" survived=0 crashed=0
    for _ in $(seq 1 20); do
        if ./"$bin" 2>&1 | grep -q "survived frees"; then survived=$((survived+1)); else crashed=$((crashed+1)); fi
    done
    printf "    %-28s survived=%-2d crashed=%-2d /20\n" "$bin" "$survived" "$crashed"
}

for R in repro_minimal repro_larger_frame; do
    echo "=== $R ==="
    for BE in x64 llvm; do
        if "$JAI" "$R.jai" -$BE -quiet >/dev/null 2>&1; then
            cp "$R" "${R}_${BE}"
            echo "  -$BE:"
            run_many "${R}_${BE}"
        else
            echo "  -$BE: BUILD FAILED"
        fi
    done
done

echo
echo "Expected on a buggy compiler (0.2.029 / 0.2.030), x64 backend:"
echo "  repro_minimal      -x64  => crashes"
echo "  repro_larger_frame -x64  => SAFE on 0.2.029, CRASHES on 0.2.030"
echo "  everything         -llvm => safe"
