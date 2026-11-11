"""The install names of the libraries macOS stubs (.tbd) re-export without
inlining them: what a link against those stubs must also find under its
system root, where the linker resolves a re-export by its install name.

    python3 tbd_reexports.py <stub.tbd>...

prints each such install name once, a line. A stub that inlines a library
(a document of its own in the same file, as libSystem's does its parts)
needs nothing more for it; one that re-exports another stub's library (as
Foundation's does CoreFoundation's) needs that stub at its install name.
"""

import re
import sys


def main(paths):
    wanted = []
    for path in paths:
        with open(path) as f:
            text = f.read()
        # A linker resolves a re-export inside the stub only when this file
        # inlines it; one another stub defines it is found by its install name.
        inlined = set(m.strip("'\"") for m in re.findall(r"^install-name:\s*(\S+)", text, re.M))
        for block in re.findall(r"^reexported-libraries:\n((?:[ -].*\n)+)", text, re.M):
            for libs in re.findall(r"libraries:\s*\[([^\]]*)\]", block):
                for name in libs.replace("\n", " ").split(","):
                    name = name.strip().strip("'\"")
                    if name and name not in inlined and name not in wanted:
                        wanted.append(name)
    for name in wanted:
        print(name)


if __name__ == "__main__":
    main(sys.argv[1:])
