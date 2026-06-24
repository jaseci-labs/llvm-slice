"""Implementations for client/llvm_slice/resolve.jac."""

impl Closure.start {
    visit [-->];
}


impl Closure.on_lib {
    if here.name in self.seen {
        skip;
    }
    self.seen.append(here.name);
    for e in here.external {
        if e not in self.external {
            self.external.append(e);
        }
    }
    visit [here ->:DependsOn:->];
}


impl _dfs_post(name: str, deps_map: dict[str, list[str]], visited: list[str], post: list[str]) -> None {
    if name in visited {
        return;
    }
    visited.append(name);
    deps: list[str] = deps_map[name] if name in deps_map else [];
    for d in deps {
        _dfs_post(d, deps_map, visited, post);
    }
    post.append(name);
}


impl _link_order(roots: list[str], deps_map: dict[str, list[str]]) -> list[str] {
    visited: list[str] = [];
    post: list[str] = [];
    for r in roots {
        _dfs_post(r, deps_map, visited, post);
    }
    post.reverse();
    return post;
}


impl resolve_closure(libs: dict[str, LibEntry], roots: list[str]) -> ClosureResult {
    # 1. Build the off-root graph.
    nodes: dict[str, LibNode] = {};
    for name in libs.keys() {
        entry: LibEntry = libs[name];
        nodes[name] = LibNode(name=name, file=entry.file, deps=entry.deps, external=entry.external);
    }
    for name in nodes.keys() {
        src: LibNode = nodes[name];
        for d in src.deps {
            if d in nodes {
                src +>:DependsOn:+> nodes[d];
            }
        }
    }

    # 2. Wire an Origin to the requested roots and walk.
    origin = Origin();
    present_roots: list[str] = [];
    missing: list[str] = [];
    for r in roots {
        if r in nodes {
            origin ++> nodes[r];
            present_roots.append(r);
        } else {
            missing.append(r);
        }
    }
    res = origin spawn Closure();
    closure_set: list[str] = res.seen;

    # 3. Order the closure for a correct static link line.
    cset: list[str] = closure_set;
    deps_map: dict[str, list[str]] = {};
    for name in closure_set {
        in_closure: list[str] = [d for d in nodes[name].deps if d in cset];
        deps_map[name] = in_closure;
    }
    order: list[str] = _link_order(present_roots, deps_map);

    total: int = 0;
    for name in closure_set {
        total += libs[name].size;
    }

    return ClosureResult(
        roots=present_roots,
        missing=missing,
        closure=order,
        external=res.external,
        total_size=total,
    );
}
