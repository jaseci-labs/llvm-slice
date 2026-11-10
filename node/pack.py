"""Collect the Node slice's tree for one platform from a build of Node.

    python3 node/pack.py <node> <platform> <out>

<node> is an unpacked Node release, configured and built by node/build.sh as
a shared library (configure --shared: out/Release/ holds the build; out/*.mk
are gyp's make files, which say what each target compiles and links). Writes,
under <out>/node/:

  <platform>/lib/          the static libraries Node's library links that the
                           toolchain ships prebuilt, compiled for a shared
                           library (position-independent, and V8's thread-local
                           storage in the model a loaded library's takes): V8
                           and what V8 is built on, ICU,
                           and Node's other dependencies, but not Node's own
                           C++ (node_base), libuv or the C libraries the
                           clibs slice ships, which neojac compiles or links
                           itself
  <platform>/include/      every header Node's own C++ reads from those
                           libraries, by the path it includes it as (their
                           include directories merged; two different files
                           of one name are an error)
  <platform>/gen/          what Node's build generates that Node's own C++ is
                           compiled with: node_javascript.cc (its JavaScript,
                           js2c), node_snapshot.cc (its startup snapshot,
                           node_mksnapshot), the inspector's protocol code,
                           and the generated headers they and Node's C++ read
  <platform>/build.json    how Node's own C++ and libuv, which neojac
                           compiles (rt/node), are built for <platform>, as
                           this build compiled them: each one's "sources",
                           "defines", "cflags", "cflags_c", "cflags_cc" and
                           "include" directories (relative to Node's tree,
                           or "gen/..." and "include" for the slice's), and
                           "reads", every file of Node's tree its compiles
                           read; and how Node's library links the slice:
                           "archives", of which "whole_archives" are linked
                           whole, as Node's own link of its library takes them
                           (on Linux each of them, as gyp links a shared
                           library's; on macOS V8's, every function of whose
                           API the library exports for the addons it loads),
                           the system "libs" and, on macOS, "frameworks"
  npm/                     npm, as Node's install lays it out
                           (lib/node_modules/npm), the same on every platform
  LICENSE                  Node's license, which covers its dependencies'

What "Node's own C++" reads is what the depfiles of node_base's and libnode's
objects list, so the tree holds exactly the headers a compile of it needs.
"""

import json
import os
import re
import shutil
import subprocess
import sys

# Archives Node's library links that are not the slice's: Node's own C++ and libuv,
# which neojac compiles (rt/node), and its startup snapshot, whose source
# (gen/node_snapshot.cc) the slice ships instead.
NOT_SLICE = {"libnode.a", "libnode_base.a", "libuv.a"}


def die(msg):
    sys.exit(f"node/pack.py: {msg}")


def mk_list(text, name):
    """The words of the make variable `name` (a `name := \\` list)."""
    m = re.search(rf"^{re.escape(name)} :=(.*?)(?:\n\n|\n[A-Za-z#])", text, re.M | re.S)
    if not m:
        return []
    return [w for w in m.group(1).replace("\\\n", " ").split() if w]


def whole_archive(thin, out):
    """`thin`, an archive gyp's make writes thin (naming its members' objects
    where they are), as an ordinary one holding them, at `out`; an ordinary
    archive (cargo's) as it is; either without debug information. AR names
    the archiver (the LLVM release's llvm-ar)."""
    with open(thin, "rb") as f:
        magic = f.read(8)
    if magic == b"!<arch>\n":
        # Already an ordinary archive (cargo's).
        shutil.copyfile(thin, out)
    else:
        ar = os.environ.get("AR", "ar").split()
        listed = subprocess.run(ar + ["t", thin], capture_output=True, text=True, check=True).stdout.split()
        base = os.path.dirname(thin)
        members = [m if os.path.isabs(m) else os.path.join(base, m) for m in listed]
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(ar + ["rcsD", out] + members, check=True)
    # Without debug information, as every slice ships its libraries: Node's
    # build compiles macOS with -gdwarf-2 (gyp's Xcode default), which makes
    # V8's archives gigabytes. STRIP names the stripper (the LLVM release's
    # llvm-strip).
    subprocess.run(os.environ.get("STRIP", "strip").split() + ["--strip-debug", out], check=True)


def depfile_paths(text):
    """The dependencies of the rule in a gyp make depfile (its `cmd_` line
    first, then `<object>: <dependency>...`)."""
    m = re.search(r"^[^\s:]+\.o:(.*?)(?:\n\n|\Z)", text, re.M | re.S)
    if not m:
        return []
    # gyp's fixed-up depfiles follow the rule with an empty one for each
    # dependency (`<header>:`), which name nothing more.
    return [w for w in m.group(1).replace("\\\n", " ").split() if w and w != "\\" and not w.endswith(":")]


def target_facts(mk_dir, build, node, gen, mk_names, gen_sources):
    """What the make files `mk_names` compile: their sources (relative to
    Node's tree; a generated one as gen/<path>), defines, flags and include
    directories (Node's tree's relative; the build's generated directories
    as gen/<path>; any other's as "include", the slice's merged headers)."""
    facts = {"sources": [], "defines": [], "cflags": [], "cflags_c": [], "cflags_cc": [], "include": []}
    for mk in mk_names:
        with open(os.path.join(mk_dir, mk)) as f:
            text = f.read()
        base = os.path.dirname(os.path.join(mk_dir, mk))
        rel_base = os.path.relpath(base, mk_dir)
        for w in mk_list(text, "OBJS"):
            if "/gen/" in w:
                facts["sources"].append("gen/" + gen_sources[w.split("/gen/", 1)[1][: -len(".o")]])
                continue
            stem = w.split("$(TARGET)/", 1)[1][: -len(".o")]
            for ext in [".cc", ".cpp", ".c", ".S", ".s"]:
                if os.path.isfile(os.path.join(node, stem + ext)):
                    facts["sources"].append(stem + ext)
                    break
            else:
                die(f"no source for {w} in {mk}")
        for key, name in [("defines", "DEFS_Release"), ("cflags", "CFLAGS_Release"), ("cflags_c", "CFLAGS_C_Release"), ("cflags_cc", "CFLAGS_CC_Release")]:
            for w in mk_list(text, name):
                if key == "defines":
                    w = w.strip("'")[2:]
                if w not in facts[key]:
                    facts[key].append(w)
        for w in mk_list(text, "INCS_Release"):
            if not w.startswith("-I"):
                continue
            d = os.path.normpath(w[2:].replace("$(srcdir)", node).replace("$(obj)", os.path.join(build, "obj")))
            if d.startswith(gen + os.sep) or d == gen:
                d = "gen/" + os.path.relpath(d, gen) if d != gen else "gen"
            elif any(d == t or d.startswith(t + os.sep) for t in [os.path.join(node, "src"), os.path.join(node, "deps", "uv")]):
                d = os.path.relpath(d, node)
            else:
                d = "include"
            if d not in facts["include"]:
                facts["include"].append(d)
    return facts


def main():
    if len(sys.argv) != 4:
        die("usage: pack.py <node> <platform> <out>")
    node, platform, out = (os.path.abspath(a) for a in sys.argv[1:])
    platform = sys.argv[2]
    build = os.path.join(node, "out", "Release")
    gen = os.path.join(build, "obj", "gen")
    mk_dir = os.path.join(node, "out")
    # The make file of Node's library (libnode.so.<ABI>, libnode.<ABI>.dylib),
    # which says how it is linked.
    with open(os.path.join(mk_dir, "libnode.target.mk")) as f:
        node_mk = f.read()
    with open(os.path.join(mk_dir, "node_base.target.mk")) as f:
        base_mk = f.read()
    dest = os.path.join(out, "node", platform)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    for d in ["lib", "include", "gen"]:
        os.makedirs(os.path.join(dest, d))
    sources = []

    # The archives, from the link of Node's library.
    m = re.search(r"^\S*/libnode\.[^\s:]+: LD_INPUTS := (.*)$", node_mk, re.M)
    if not m:
        die("libnode.target.mk has no LD_INPUTS for Node's library: is Node configured --shared?")
    archives = []
    for w in m.group(1).split():
        if not w.endswith(".a"):
            continue
        # gyp's make names a static library by $(obj) (Linux) or by the
        # product directory, $(builddir) (macOS).
        path = w.replace("$(obj)", os.path.join(build, "obj")).replace("$(builddir)", build)
        name = os.path.basename(path)
        if name in NOT_SLICE:
            continue
        if not os.path.isfile(path):
            die(f"Node's library links {path}, which is not there")
        whole_archive(path, os.path.join(dest, "lib", name))
        archives.append(name)
    flags = mk_list(node_mk, "LDFLAGS_Release")
    with open(os.path.join(mk_dir, "Makefile")) as f:
        solink = re.search(r"^cmd_solink = (.*)$", f.read(), re.M)
    if solink and re.search(r"--whole-archive \$\(LD_INPUTS\)", solink.group(1)):
        # gyp's make links a shared library's static inputs whole (Linux).
        whole = list(archives)
    else:
        # macOS: each archive the link names to load whole.
        whole = []
        for w in flags:
            if w.startswith("-Wl,-force_load,"):
                name = os.path.basename(w[len("-Wl,-force_load,") :])
                if name in archives and name not in whole:
                    whole.append(name)
    if not whole:
        die("Node's library links no archive whole")
    libs = [w[2:] for w in mk_list(node_mk, "LIBS") if w.startswith("-l")]
    # Static libraries Node's library links by path in LIBS: the Rust crates V8's
    # Temporal is built on (libnode_crates.a, cargo's).
    for w in mk_list(node_mk, "LIBS"):
        if w.endswith(".a"):
            path = os.path.normpath(w.replace("$(obj)", os.path.join(build, "obj")).replace("$(builddir)", build))
            name = os.path.basename(path)
            if not os.path.isfile(path):
                die(f"Node's library links {path}, which is not there")
            if name not in archives:
                whole_archive(path, os.path.join(dest, "lib", name))
                archives.append(name)
    # macOS: the frameworks Node's link names (-framework <name>).
    frameworks = []
    words = mk_list(node_mk, "LIBS") + flags
    for k, w in enumerate(words):
        if w == "-framework" and k + 1 < len(words) and words[k + 1] not in frameworks:
            frameworks.append(words[k + 1])

    # The headers Node's own C++ reads outside its tree and libuv, by the
    # include directory each is found through; the generated sources and
    # headers.
    roots = []
    for w in mk_list(base_mk, "INCS_Release"):
        if not w.startswith("-I"):
            continue
        d = w[2:].replace("$(srcdir)", node).replace("$(obj)", os.path.join(build, "obj"))
        roots.append(os.path.normpath(d))
    own = [os.path.join(node, "src"), os.path.join(node, "deps", "uv"), gen]
    placed = {}
    reads = {"node": set(), "uv": set()}
    deps_dir = os.path.join(build, ".deps")
    for walked, _, names in os.walk(deps_dir):
        target = walked.replace("\\", "/") + "/"
        if "/obj.target/libuv/" in target:
            for name in names:
                if name.endswith(".o.d"):
                    with open(os.path.join(walked, name)) as f:
                        for p in depfile_paths(f.read()):
                            p = os.path.normpath(p if os.path.isabs(p) else os.path.join(mk_dir, p))
                            if p.startswith(os.path.join(node, "deps", "uv") + os.sep):
                                reads["uv"].add(os.path.relpath(p, node))
            continue
        if "/obj.target/node_base/" not in target and "/obj.target/libnode/" not in target:
            continue
        for name in names:
            if not name.endswith(".o.d"):
                continue
            with open(os.path.join(walked, name)) as f:
                for p in depfile_paths(f.read()):
                    p = os.path.normpath(p if os.path.isabs(p) else os.path.join(mk_dir, p))
                    if not p.startswith(node + os.sep):
                        continue  # the toolchain's and the system's
                    if p.startswith(gen + os.sep):
                        rel = os.path.relpath(p, gen)
                        os.makedirs(os.path.dirname(os.path.join(dest, "gen", rel)), exist_ok=True)
                        shutil.copyfile(p, os.path.join(dest, "gen", rel))
                        continue
                    if any(p.startswith(o + os.sep) for o in own):
                        reads["node"].add(os.path.relpath(p, node))
                        continue
                    root = max((r for r in roots if p.startswith(r + os.sep)), key=len, default="")
                    if root == "":
                        die(f"Node's C++ reads {p}, under none of its include directories")
                    rel = os.path.relpath(p, root)
                    if rel in placed and placed[rel] != p:
                        die(f"two headers are included as {rel}: {placed[rel]} and {p}")
                    placed[rel] = p
    for rel, p in sorted(placed.items()):
        os.makedirs(os.path.dirname(os.path.join(dest, "include", rel)), exist_ok=True)
        shutil.copyfile(p, os.path.join(dest, "include", rel))
    # The generated sources Node's own C++ is compiled with.
    sources = []
    gen_sources = {}
    for mk in ["node_base.target.mk", "libnode.target.mk"]:
        with open(os.path.join(mk_dir, mk)) as f:
            for w in mk_list(f.read(), "OBJS"):
                if "/gen/" in w:
                    stem = w.split("/gen/", 1)[1][: -len(".o")]
                    for ext in [".cc", ".cpp"]:
                        if os.path.isfile(os.path.join(gen, stem + ext)):
                            rel = stem + ext
                            break
                    else:
                        die(f"no generated source for {w}")
                    os.makedirs(os.path.dirname(os.path.join(dest, "gen", rel)), exist_ok=True)
                    shutil.copyfile(os.path.join(gen, rel), os.path.join(dest, "gen", rel))
                    sources.append(rel)
                    gen_sources[stem] = rel
    facts = {
        "node": target_facts(mk_dir, build, node, gen, ["node_base.target.mk", "libnode.target.mk"], gen_sources),
        "uv": target_facts(mk_dir, build, node, gen, [os.path.join("deps", "uv", "libuv.target.mk")], gen_sources),
        "archives": archives,
        "whole_archives": whole,
        "libs": libs,
        "frameworks": frameworks,
    }
    facts["node"]["reads"] = sorted(reads["node"])
    facts["uv"]["reads"] = sorted(reads["uv"])
    with open(os.path.join(dest, "build.json"), "w") as f:
        json.dump(facts, f, indent=2)
        f.write("\n")

    # npm, as `make install` lays it out, and Node's license.
    npm = os.path.join(out, "node", "npm")
    if os.path.isdir(npm):
        shutil.rmtree(npm)
    shutil.copytree(os.path.join(node, "deps", "npm"), npm, symlinks=True)
    shutil.copyfile(os.path.join(node, "LICENSE"), os.path.join(out, "node", "LICENSE"))
    print(
        f"node/pack.py: {platform}: {len(archives)} archives ({len(whole)} whole), "
        f"{len(placed)} headers, {len(sources)} generated sources"
    )


if __name__ == "__main__":
    main()
