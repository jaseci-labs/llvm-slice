"""Dependency-closure resolution over the LLVM library graph.

This is the object-spatial heart of the client. Given a manifest's library map
and a set of root libraries the consumer wants to link, we:

  1. Build an in-memory graph: one LibNode per library, a DependsOn edge per
     internal dependency. The graph is deliberately built OFF `root` so nothing
     persists between CLI runs.
  2. Spawn a Closure walker from an Origin node wired to the requested roots.
     The walker traverses DependsOn edges, accumulating the reachable set and
     merging every external (non-LLVM) link requirement it encounters.
  3. Order the reachable set into a valid static link line (each library before
     its dependencies) via a depth-first post-order, which is what a linker and
     `llvm-config --libs` both expect."""

import from lib.model { LibEntry }


node LibNode {
    has name: str;
    has file: str | None = None;
    has deps: list[str] = [];
    has external: list[str] = [];
}

edge DependsOn: LibNode --> LibNode {}

node Origin {}


walker Closure {
    has seen: list[str] = [];       # reachable closure, in BFS discovery order
    has external: list[str] = [];   # merged external requirements, deduped, first-seen order

    can start with Origin entry {
        visit [-->];
    }

    can on_lib with LibNode entry {
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
}


obj ClosureResult {
    has roots: list[str] = [];        # requested roots that exist in the manifest
    has missing: list[str] = [];      # requested roots NOT in the manifest
    has closure: list[str] = [];      # full closure in static link order (dependents first)
    has external: list[str] = [];     # merged external link requirements
    has total_size: int = 0;          # sum of member sizes in the closure (bytes)
}


# Depth-first post-order over the closure's internal edges, then reversed, yields
# a static link order: every library appears before the libraries it depends on.
# A `visited` set makes it safe against the occasional dependency cycle.
def _dfs_post(name: str, deps_map: dict[str, list[str]], visited: list[str], post: list[str]) -> None {
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


def _link_order(roots: list[str], deps_map: dict[str, list[str]]) -> list[str] {
    visited: list[str] = [];
    post: list[str] = [];
    for r in roots {
        _dfs_post(r, deps_map, visited, post);
    }
    post.reverse();
    return post;
}


# Compute the transitive closure of `roots` over `libs` (a name -> LibEntry map),
# returning the link-ordered closure plus merged external requirements.
def resolve_closure(libs: dict[str, LibEntry], roots: list[str]) -> ClosureResult {
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
