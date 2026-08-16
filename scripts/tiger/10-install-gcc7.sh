#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
ensure_layout
for archive in \
    "gcc7-$GCC_VERSION-tiger-ppc.tar.gz" \
    "gmp-$GMP_VERSION.tar.bz2" \
    "mpfr-$MPFR_VERSION.tar.bz2" \
    "isl-$ISL_VERSION.tar.bz2" \
    "mpc-$MPC_VERSION.tar.gz"; do
    require_source "$archive"
done
start_log 10-install-gcc7

run_root mkdir -p "$PREFIX"
run_root /usr/bin/tar xzf "$SOURCES_DIR/gcc7-$GCC_VERSION-tiger-ppc.tar.gz" -C "$PREFIX"
require_file "$GCC"

extract_source "gmp-$GMP_VERSION.tar.bz2" "gmp-$GMP_VERSION"
cd "$EXTRACTED_SOURCE"
ABI=32 CC=/usr/bin/gcc CFLAGS=-m32 LDFLAGS=-m32 ./configure \
    --prefix="$PREFIX" --enable-shared --enable-static --disable-assembly
/usr/bin/sed -i '' 's|/\* #undef PACKAGE_VERSION \*/|#define PACKAGE_VERSION "'"$GMP_VERSION"'"|' config.h
/usr/bin/sed -i '' 's|/\* #undef VERSION \*/|#define VERSION "'"$GMP_VERSION"'"|' config.h
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install

extract_source "mpfr-$MPFR_VERSION.tar.bz2" "mpfr-$MPFR_VERSION"
cd "$EXTRACTED_SOURCE"
CC=/usr/bin/gcc CFLAGS=-m32 LDFLAGS="-L$PREFIX/lib -m32" ./configure \
    --prefix="$PREFIX" --with-gmp="$PREFIX" --enable-shared --disable-static
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install

extract_source "isl-$ISL_VERSION.tar.bz2" "isl-$ISL_VERSION"
cd "$EXTRACTED_SOURCE"
CC=/usr/bin/gcc CFLAGS=-m32 LDFLAGS="-L$PREFIX/lib -m32" ./configure \
    --prefix="$PREFIX" --with-gmp-prefix="$PREFIX" --enable-shared --disable-static
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install

extract_source "mpc-$MPC_VERSION.tar.gz" "mpc-$MPC_VERSION"
cd "$EXTRACTED_SOURCE"
CC=/usr/bin/gcc CFLAGS=-m32 LDFLAGS="-L$PREFIX/lib -m32" ./configure \
    --prefix="$PREFIX" --with-gmp="$PREFIX" --with-mpfr="$PREFIX" \
    --enable-shared --disable-static
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install

run_root mkdir -p "$PREFIX/lib/gcc/7" "$PREFIX/bin"
runtime_count=0
for runtime_path in "$GCC_LIB"/*.dylib; do
    [ -e "$runtime_path" ] || [ -L "$runtime_path" ] || continue
    runtime=$(/usr/bin/basename "$runtime_path")
    run_root ln -sfn "$runtime_path" "$PREFIX/lib/gcc/7/$runtime"
    runtime_count=$((runtime_count + 1))
done
[ "$runtime_count" -gt 0 ] || die "GCC runtime directory contains no dylibs"
for tool in gcc-7 g++-7 cpp-7; do
    [ -x "$GCC_PREFIX/bin/$tool" ] && run_root ln -sfn "$GCC_PREFIX/bin/$tool" "$PREFIX/bin/$tool"
done

# Rebuild GMP after the compiler runtime is complete so libgmpxx uses the
# GCC 7 C++11 ABI rather than Tiger's GCC 4 libstdc++ ABI.
extract_source "gmp-$GMP_VERSION.tar.bz2" "gmp-$GMP_VERSION-cxx"
cd "$EXTRACTED_SOURCE"
ABI=32 CC=/usr/bin/gcc CXX="$GXX" CFLAGS=-m32 \
    CXXFLAGS="-O2 -m32 -mcpu=970 -mtune=970" \
    LDFLAGS="-L$PREFIX/lib -L$GCC_LIB -m32" ./configure \
    --prefix="$PREFIX" --enable-cxx --enable-shared --enable-static \
    --disable-assembly
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install

test_c="$WORK_DIR/gcc-smoke.c"
printf '%s\n' '#include <stdio.h>' 'int main(void) { puts("gcc7-ok"); return 0; }' > "$test_c"
"$GCC" -O2 -mcpu=970 -fstack-protector-all \
    "$test_c" -o "$WORK_DIR/gcc-smoke"
"$WORK_DIR/gcc-smoke"

test_cxx="$WORK_DIR/gmpxx-smoke.cpp"
printf '%s\n' '#include <gmpxx.h>' '#include <string>' \
    'int main(void) { mpz_class value(std::string("42")); return value == 42 ? 0 : 1; }' \
    > "$test_cxx"
"$GXX" -O2 -mcpu=970 -fstack-protector-all -I"$PREFIX/include" \
    "$test_cxx" -L"$PREFIX/lib" -lgmpxx -lgmp -o "$WORK_DIR/gmpxx-smoke"
/usr/bin/otool -L "$WORK_DIR/gmpxx-smoke" | /usr/bin/grep libgmpxx
"$WORK_DIR/gmpxx-smoke"
log "GCC $GCC_VERSION and runtime dependencies installed"
