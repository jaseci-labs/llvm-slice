"""Tests for dependency-closure resolution, using a small diamond graph that
mirrors the real LLVM bottom layer (Core -> Support/BinaryFormat -> Demangle)."""


def _fixture() -> dict[str, LibEntry] {
    libs: dict[str, LibEntry] = {};
    libs["LLVMDemangle"] = LibEntry(name="LLVMDemangle", file="lib/libLLVMDemangle.a", size=50);
    libs["LLVMSupport"] = LibEntry(
        name="LLVMSupport", file="lib/libLLVMSupport.a", size=100,
        deps=["LLVMDemangle"], external=["-lpthread", "ZLIB::ZLIB"]
    );
    libs["LLVMBinaryFormat"] = LibEntry(
        name="LLVMBinaryFormat", file="lib/libLLVMBinaryFormat.a", size=30, deps=["LLVMSupport"]
    );
    libs["LLVMCore"] = LibEntry(
        name="LLVMCore", file="lib/libLLVMCore.a", size=200,
        deps=["LLVMSupport", "LLVMBinaryFormat"], external=["-lpthread"]
    );
    libs["LLVMX86CodeGen"] = LibEntry(
        name="LLVMX86CodeGen", file="lib/libLLVMX86CodeGen.a", size=300, deps=["LLVMCore"]
    );
    return libs;
}


test "single root closure, link order, external, size" {
    libs = _fixture();
    r = resolve_closure(libs, ["LLVMX86CodeGen"]);
    assert sorted(r.closure) == ["LLVMBinaryFormat", "LLVMCore", "LLVMDemangle", "LLVMSupport", "LLVMX86CodeGen"];
    assert r.closure == ["LLVMX86CodeGen", "LLVMCore", "LLVMBinaryFormat", "LLVMSupport", "LLVMDemangle"];
    assert r.external == ["-lpthread", "ZLIB::ZLIB"];
    assert r.total_size == 680;
    assert r.missing == [];
}

test "link-order invariant: every lib precedes its dependencies" {
    libs = _fixture();
    r = resolve_closure(libs, ["LLVMX86CodeGen"]);
    for name in r.closure {
        for d in libs[name].deps {
            if d in r.closure {
                assert r.closure.index(name) < r.closure.index(d), f"{name} must precede {d}";
            }
        }
    }
}

test "missing root reported, no closure" {
    libs = _fixture();
    r = resolve_closure(libs, ["LLVMNope"]);
    assert r.missing == ["LLVMNope"];
    assert r.closure == [];
    assert r.total_size == 0;
    assert r.external == [];
}

test "multi-root closure is the union with a valid order" {
    libs = _fixture();
    r = resolve_closure(libs, ["LLVMCore", "LLVMX86CodeGen"]);
    assert sorted(r.closure) == ["LLVMBinaryFormat", "LLVMCore", "LLVMDemangle", "LLVMSupport", "LLVMX86CodeGen"];
    assert r.roots == ["LLVMCore", "LLVMX86CodeGen"];
    for name in r.closure {
        for d in libs[name].deps {
            if d in r.closure {
                assert r.closure.index(name) < r.closure.index(d);
            }
        }
    }
}
