#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_dir "$GCC_PREFIX"
stage_copy "$GCC_PREFIX" "/usr/local/gcc7"

for library in libgmp libgmpxx libmpfr libisl libmpc; do
    stage_copy_library_family "$library"
done
for header in gmp.h gmpxx.h mpfr.h mpc.h; do
    [ ! -f "$PREFIX/include/$header" ] || \
        stage_copy "$PREFIX/include/$header" /usr/local/include
done
stage_require_dir "$PREFIX/include/isl"
stage_copy "$PREFIX/include/isl" /usr/local/include

for pc in gmp gmpxx mpfr isl mpc; do
    [ ! -f "$PREFIX/lib/pkgconfig/$pc.pc" ] || \
        stage_copy "$PREFIX/lib/pkgconfig/$pc.pc" /usr/local/lib/pkgconfig
done

runtime_count=0
for runtime_path in "$GCC_LIB"/*.dylib; do
    [ -e "$runtime_path" ] || [ -L "$runtime_path" ] || continue
    runtime=$(/usr/bin/basename "$runtime_path")
    stage_symlink "$runtime_path" "/usr/local/lib/gcc/7/$runtime"
    runtime_count=$((runtime_count + 1))
done
[ "$runtime_count" -gt 0 ] || die "GCC runtime directory contains no dylibs"
