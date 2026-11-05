#!/bin/sh
# LLVM's runtimes for one target, built by LLVM's own CMake from the pinned
# sources with the pinned Clang: compiler-rt's builtins, then libunwind,
# libc++abi and libc++ (static libraries only).
#
#   runtimes/llvm-runtimes.sh <triple> <out> builtins|cxx
#
# <triple> is x86_64-linux-musl, aarch64-linux-musl, x86_64-linux-gnu,
# aarch64-linux-gnu, x86_64-w64-mingw32, arm64-apple-macosx or
# x86_64-apple-macosx. The target's C library comes from the environment:
#
#   LIBC_INCLUDES  include directories, in search order (Linux targets)
#   MINGW_SYSROOT  a mingw-w64 sysroot (<triple>/include, <triple>/lib)
#   SDKROOT        a macOS SDK
#
# Writes <out>/lib (libclang_rt.builtins.a; libunwind.a, libc++abi.a, libc++.a)
# and, for cxx, <out>/include (c++/v1 with its __config_site, and libunwind's).
#
# The C++ runtime is linked statically into programs and shared libraries, so
# it is hermetic: its libraries export nothing. A program's references to it
# then bind inside the program, never to another copy of libc++ in the
# process: on macOS, dyld coalesces exported weak C++ definitions with the
# system's own libc++, which every process loads.
. "$(dirname "$0")/lib.sh"
triple="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
phase="$3"
llvm_toolchain
llvm_sources

res="$("$LLVM/bin/clang" -print-resource-dir)"
arch="${triple%%-*}"
cmake_arch="$arch"
flags="-ffunction-sections -fdata-sections"
extra=""
case "$triple" in
    *-linux-*)
        system=Linux
        # The include order `neojac cc` gives the programs it compiles:
        # Clang's resource headers, then the C library's.
        flags="$flags -nostdinc -isystem $res/include"
        for d in ${LIBC_INCLUDES:?LIBC_INCLUDES names the target C library headers}; do
            flags="$flags -isystem $d"
        done
        case "$triple" in
            # The oldest glibc neojac targets: the C++ runtime links at every
            # newer one.
            *-gnu) flags="$flags -D__GLIBC_MINOR__=17" ;;
            *-musl) extra="-DLIBCXX_HAS_MUSL_LIBC=ON" ;;
        esac
        # The checks of a static-library build compile without linking, so
        # they find every function the headers declare and every library they
        # ask for, and the answers have to be given:
        # - musl has no __cxa_thread_atexit_impl, and glibc has it only from
        #   2.18: libc++abi must reach it weakly, through its fallback, not
        #   call it outright.
        # - The C library's parts (libpthread, libdl, librt, libatomic) are
        #   the link's to name: a runtime that found them would name them
        #   itself, in its objects (#pragma comment(lib)), and LLD would look
        #   for them on its own.
        # (check_links.py proves every reference resolves at the floor, and
        # that no library names another.)
        extra="$extra -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF
            -DLIBCXX_HAS_PTHREAD_LIB=OFF -DLIBCXX_HAS_RT_LIB=OFF -DLIBCXX_HAS_ATOMIC_LIB=OFF
            -DLIBCXXABI_HAS_PTHREAD_LIB=OFF -DLIBCXXABI_HAS_DL_LIB=OFF
            -DLIBUNWIND_HAS_PTHREAD_LIB=OFF -DLIBUNWIND_HAS_DL_LIB=OFF"
        ;;
    *-mingw32)
        system=Windows
        flags="$flags --sysroot=${MINGW_SYSROOT:?MINGW_SYSROOT names the mingw-w64 sysroot}"
        # Windows' own threads, as llvm-mingw builds it: libc++ would otherwise
        # pick winpthreads (its <pthread.h> is in the sysroot), and every C++
        # program would need it.
        extra="-DLIBCXX_HAS_WIN32_THREAD_API=ON"
        ;;
    *-apple-macosx)
        system=Darwin
        cmake_arch="$(echo "$arch" | sed 's/^aarch64$/arm64/')"
        extra="-DCMAKE_OSX_SYSROOT=${SDKROOT:?SDKROOT names the macOS SDK} -DCMAKE_OSX_ARCHITECTURES=$cmake_arch -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0"
        ;;
    *) die "unknown target $triple" ;;
esac

common="-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$out/install
    -DCMAKE_C_COMPILER=$LLVM/bin/clang -DCMAKE_CXX_COMPILER=$LLVM/bin/clang++ -DCMAKE_ASM_COMPILER=$LLVM/bin/clang
    -DCMAKE_C_COMPILER_TARGET=$triple -DCMAKE_CXX_COMPILER_TARGET=$triple -DCMAKE_ASM_COMPILER_TARGET=$triple
    -DCMAKE_AR=$LLVM/bin/llvm-ar -DCMAKE_RANLIB=$LLVM/bin/llvm-ranlib -DCMAKE_NM=$LLVM/bin/llvm-nm
    -DCMAKE_SYSTEM_NAME=$system -DCMAKE_SYSTEM_PROCESSOR=$cmake_arch
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF $extra"

build="$WORK/llvm-runtimes-$triple-$phase"
rm -rf "$build" "$out/install"
case "$phase" in
    builtins)
        # shellcheck disable=SC2086
        cmake $common -S "$LLVM_SRC/compiler-rt" -B "$build" \
            -DCMAKE_C_FLAGS="$flags" -DCMAKE_ASM_FLAGS="$flags" \
            -DCOMPILER_RT_BUILD_BUILTINS=ON -DCOMPILER_RT_BUILD_CRT=OFF \
            -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
            -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
            -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
            -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
            -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_BAREMETAL_BUILD=OFF \
            -DCOMPILER_RT_ENABLE_IOS=OFF -DCOMPILER_RT_ENABLE_WATCHOS=OFF \
            -DCOMPILER_RT_ENABLE_TVOS=OFF -DCOMPILER_RT_ENABLE_XROS=OFF \
            -DDARWIN_osx_ARCHS="$cmake_arch" -DDARWIN_osx_BUILTIN_ARCHS="$cmake_arch"
        ninja -C "$build" install
        lib="$(find "$out/install" -name 'libclang_rt.builtins*.a' -o -name 'libclang_rt.osx.a' | head -1)"
        [ -n "$lib" ] || die "$triple: no builtins library was installed"
        mkdir -p "$out/lib"
        cp "$lib" "$out/lib/libclang_rt.builtins.a"
        ;;
    cxx)
        # shellcheck disable=SC2086
        cmake $common -S "$LLVM_SRC/runtimes" -B "$build" \
            -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_ASM_FLAGS="$flags" \
            -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
            -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_USE_COMPILER_RT=ON \
            -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_USE_COMPILER_RT=ON \
            -DLIBCXXABI_USE_LLVM_UNWINDER="$( [ "$system" = Darwin ] && echo OFF || echo ON )" \
            -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_USE_COMPILER_RT=ON \
            -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=OFF \
            -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON -DLIBCXXABI_HERMETIC_STATIC_LIBRARY=ON \
            -DLIBUNWIND_HIDE_SYMBOLS=ON \
            -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF \
            -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF \
            -DLIBCXX_INCLUDE_DOCS=OFF -DLIBUNWIND_INCLUDE_DOCS=OFF -DLLVM_INCLUDE_TESTS=OFF
        ninja -C "$build" install-unwind install-cxxabi install-cxx
        mkdir -p "$out/lib"
        for l in libc++.a libc++abi.a libunwind.a; do
            if [ "$system" = Darwin ] && [ "$l" = libunwind.a ]; then continue; fi
            cp "$out/install/lib/$l" "$out/lib/$l"
        done
        rm -rf "$out/include"
        cp -R "$out/install/include" "$out/include"
        test -f "$out/include/c++/v1/__config_site"
        ;;
    *) die "phase is builtins or cxx" ;;
esac
rm -rf "$out/install"
log "$triple $phase: $(ls "$out/lib" | tr '\n' ' ')"
