# The CPython slice

What a toolchain that compiles CPython's C itself needs from the rest of a
CPython build: the parts of CPython's release that are not C, the standard
library, the frozen modules and typeshed's stubs of the standard library.
The C libraries the standard library is built on are the clibs slice's
(`clibs/`), which Node's are too. It is published as release
`cpython-v<version>-<revision>`: `cpython-<version>-dev.zip`, a zip in the dev
slices' format (one DEFLATE member per file and a central directory, so a
client range-fetches what it needs), and `cpython-<version>-manifest.json`,
which names every member's size and sha256 (`docs/manifest-schema.md`). A
consumer pins the manifest by its sha256; neojac ships the tree in its `lib/`,
beside the runtimes slice's.

| Path | What |
|---|---|
| `cpython/lib/python3.15/` | the standard library (`Lib/`), as an installed interpreter lays it out, less the test suite, IDLE and Tk (`tkinter`, `turtle`, `turtledemo`) |
| `cpython/frozen/Python/frozen_modules/` | the frozen modules a native build writes, where CPython's C includes them from |
| `cpython/typeshed/{LICENSE,stdlib/}` | typeshed's stubs of the standard library, and its `VERSIONS`: those of the modules the standard library above has (in 3.15 by `VERSIONS`, and not Tk's), for a checker's types |
| `cpython/SOURCES.txt` | every pinned input |

## How each piece is made

Every input is pinned by sha256 in `sources.txt`.

| Piece | Script | How |
|---|---|---|
| the standard library and frozen modules | `stdlib.sh`, `stdlib.py` | CPython's configure and make of the frozen modules alone (`Programs/_freeze_module` and the interpreter it bootstraps), natively with the host's compiler |
| typeshed's stubs | `stdlib.sh`, `stdlib.py` | typeshed's `stdlib/` at a pinned commit, unchanged, less the stubs of modules the standard library doesn't have |

`.github/workflows/build-cpython.yml` runs it all, and `scripts/pack_slice.jac`
packs the tree.
