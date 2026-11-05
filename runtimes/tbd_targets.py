"""Restrict a text stub (.tbd) to the architectures LLVM's TextAPI reads.

    python3 tbd_targets.py <Architecture.def> <in.tbd> <out.tbd>

Every `targets: [ ... ]` list keeps the targets whose architecture (the part
before the first `-`) Architecture.def names; the rest of the stub is copied as
it is. A list whose targets are all unknown is an error: the stub would then
describe nothing.
"""

import re
import sys


def known_architectures(def_path: str) -> set[str]:
    # ARCHINFO(arm64e, arm64e, MachO::CPU_TYPE_ARM64, MachO::CPU_SUBTYPE_ARM64E, 64)
    with open(def_path) as f:
        names = set(re.findall(r"^ARCHINFO\(\s*\w+\s*,\s*([\w.]+)\s*,", f.read(), re.M))
    if not names:
        sys.exit(f"tbd_targets: {def_path} names no architectures")
    return names


def main() -> None:
    def_path, src, dst = sys.argv[1:4]
    known = known_architectures(def_path)
    with open(src) as f:
        text = f.read()

    def keep(m: re.Match) -> str:
        targets = [t.strip() for t in m.group(2).split(",") if t.strip()]
        kept = [t for t in targets if t.split("-", 1)[0] in known]
        if not kept:
            sys.exit(f"tbd_targets: no target of [{', '.join(targets)}] is one TextAPI knows")
        return f"{m.group(1)}[ {', '.join(kept)} ]"

    out = re.sub(r"(targets:\s*)\[([^\]]*)\]", keep, text)
    with open(dst, "w") as f:
        f.write(out)


if __name__ == "__main__":
    main()
