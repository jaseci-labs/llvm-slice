# Consuming a slice

After `llvm-slice fetch`, you have a directory with exactly the libraries you
asked for (in dependency closure), plus optionally the headers and CMake package
files:

```bash
llvm-slice fetch --version 18.1.8 --triple x86_64-linux-gnu-ubuntu-18.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen --headers --cmake -o ./slice
```

```
slice/
├── lib/
│   ├── libLLVMOrcJIT.a
│   ├── libLLVMX86CodeGen.a
│   ├── …                       # the full closure of the requested libs
│   └── cmake/llvm/...          # only if --cmake was passed
├── include/...                 # only if --headers was passed
└── manifest.json
```

There are two ways to link it.

## Option A — raw link line (recommended for slices)

`llvm-slice resolve` prints the closure in correct static link order (each
library before its dependencies) and the external requirements:

```bash
llvm-slice resolve --version 18.1.8 --triple x86_64-linux-gnu-ubuntu-18.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen
# closure: 57 libraries (static link order, dependents first)
#   LLVMX86CodeGen LLVMX86Desc … LLVMCore … LLVMSupport LLVMDemangle
# external link requirements: 6
#   -lpthread rt dl m ZLIB::ZLIB Terminfo::terminfo
```

Turn that into a link line: point `-L` at `slice/lib`, list the closure as
`-l<name>` in the printed order, then add the externals (mapped to flags):

```bash
clang++ main.cpp -I ./slice/include \
  -L ./slice/lib \
  -lLLVMX86CodeGen -lLLVMX86Desc … -lLLVMCore -lLLVMSupport -lLLVMDemangle \
  -lpthread -lrt -ldl -lm -lz -ltinfo
```

Because the closure is already in dependency order, you do not need
`--start-group/--end-group`. (If you ever hit a genuine dependency cycle, wrap
the LLVM libs in `-Wl,--start-group … -Wl,--end-group`.)

### External requirement → link flag

`external` entries are upstream's `INTERFACE_LINK_LIBRARIES` system tokens,
passed through verbatim. Map them as:

| manifest token        | link flag        |
|-----------------------|------------------|
| `-lpthread`           | `-lpthread`      |
| `m`                   | `-lm`            |
| `dl`                  | `-ldl`           |
| `rt`                  | `-lrt`           |
| `ZLIB::ZLIB`          | `-lz`            |
| `zstd`, `libzstd::libzstd` | `-lzstd`    |
| `Terminfo::terminfo`  | `-ltinfo` (or `-lncurses`) |
| `-l…` / bare name     | as-is / prefix `-l` |

The `::`-style tokens are CMake imported targets; on a plain link line use the
flag above, or satisfy them with your distro's `-dev` packages.

## Option B — `find_package(LLVM)` via CMake

If you fetched with `--cmake --headers`, the slice contains `lib/cmake/llvm`, so
`find_package(LLVM CONFIG)` works:

```cmake
# cmake -DLLVM_DIR=/abs/path/to/slice/lib/cmake/llvm
find_package(LLVM REQUIRED CONFIG)
llvm_map_components_to_libnames(LLVM_LIBS orcjit x86codegen)
add_executable(app main.cpp)
target_include_directories(app PRIVATE ${LLVM_INCLUDE_DIRS})
target_link_libraries(app PRIVATE ${LLVM_LIBS})
```

or set it on the command line:

```bash
cmake -B build -DCMAKE_PREFIX_PATH=/abs/path/to/slice
```

**Caveat:** the IMPORTED targets reference every LLVM library by absolute path,
but only the closure you fetched is on disk. CMake checks a target's file only
when that target is actually linked, so this works **as long as every component
you map is within the closure you fetched**. If you map a component outside the
closure, re-run `fetch` with it included (or fetch the full set). You may also
need `find_package(ZLIB)` / `find_package(zstd)` / a terminfo lib available so
the transitively-referenced system targets resolve.

## Why a zip (not the original tar.xz)

The official `clang+llvm-*.tar.xz` is a solid `xz` stream with no seekable
index, so extracting one file means decompressing the whole multi-GB stream. The
dev zip uses per-member DEFLATE with a central directory, so `llvm-slice fetch`
pulls just the members in your closure over HTTP Range requests — typically a
few percent of the full archive. (SOZip is unnecessary here: the members are
many separate `.a`/`.lib` files, so per-member random access from the ordinary
ZIP central directory already suffices.)
