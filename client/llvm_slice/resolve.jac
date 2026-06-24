"""Dependency-closure resolution over the LLVM library graph.

The object-spatial heart of the client. Given a manifest's library map and a set
of root libraries, we build an in-memory graph (one LibNode per library, a
DependsOn edge per internal dependency, deliberately OFF `root` so nothing
persists between runs), spawn a Closure walker from an Origin wired to the
requested roots to gather the reachable set + merged externals, then order the
closure into a valid static link line (each library before its dependencies) via
a DFS post-order. Bodies live in impl/resolve.impl.jac."""

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

    can start with Origin entry;
    can on_lib with LibNode entry;
}


obj ClosureResult {
    has roots: list[str] = [];        # requested roots that exist in the manifest
    has missing: list[str] = [];      # requested roots NOT in the manifest
    has closure: list[str] = [];      # full closure in static link order (dependents first)
    has external: list[str] = [];     # merged external link requirements
    has total_size: int = 0;          # sum of member sizes in the closure (bytes)
}


# Depth-first post-order over the closure's internal edges; reversed by
# _link_order it yields a static link order. A `visited` list guards cycles.
def _dfs_post(name: str, deps_map: dict[str, list[str]], visited: list[str], post: list[str]) -> None;

def _link_order(roots: list[str], deps_map: dict[str, list[str]]) -> list[str];

# Compute the transitive closure of `roots` over `libs` (a name -> LibEntry map),
# returning the link-ordered closure plus merged external requirements.
def resolve_closure(libs: dict[str, LibEntry], roots: list[str]) -> ClosureResult;
