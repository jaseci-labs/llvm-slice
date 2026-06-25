"""llvm-slice: fetch only the LLVM static libraries you link.

  llvm-slice list    --version V --triple T
  llvm-slice resolve --version V --triple T --libs LLVMOrcJIT,LLVMX86CodeGen
  llvm-slice fetch   --version V --triple T --libs ... [--headers] [--cmake] -o DIR

Run from the repo root:  jac run llvm_slice/cli.jac <subcommand> ...
Asset source defaults to the GitHub releases of jaseci-labs/llvm-slice; override
with --repo / env LLVM_SLICE_REPO, or point --base-url at a local directory.
Args are parsed by hand (the stdlib argparse objects are untyped at the Jac
boundary). Bodies live in impl/cli.impl.jac."""

import sys;
import from llvm_slice.fetcher { load_manifest, fetch_slice }
import from llvm_slice.resolve { resolve_closure }


obj Args {
    has cmd: str = "";
    has version: str = "";
    has triple: str = "";
    has repo: str = "";
    has base_url: str = "";
    has libs: str = "";
    has out: str = "./out";
    has headers: bool = False;
    has cmake: bool = False;
    has ok: bool = True;
    has error: str = "";
}


def _split_libs(s: str) -> list[str];
def _pct(part: int, whole: int) -> str;
def parse_args(argv: list[str]) -> Args;
def _require_common(a: Args) -> bool;
def cmd_list(a: Args) -> int;
def cmd_resolve(a: Args) -> int;
def cmd_fetch(a: Args) -> int;
def usage() -> None;

# Console-script entry (jac.toml [entrypoints.scripts]). Returns the process
# exit code so the pip-generated launcher can `sys.exit(main())`; the same
# function backs `jac run` via the `with entry` block below.
def main() -> int;


with entry {
    sys.exit(main());
}
