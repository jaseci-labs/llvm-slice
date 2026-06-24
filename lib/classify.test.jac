"""Tests for asset classification against real upstream asset names."""


test "clang+llvm family, tar.xz" {
    k = classify_asset("clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz", "18.1.8");
    assert k is not None;
    assert k.triple == "x86_64-linux-gnu-ubuntu-18.04";
    assert k.family == "clang+llvm";
    assert k.ext == "tar.xz";
}

test "clang+llvm family, tar.gz" {
    k = classify_asset("clang+llvm-18.1.8-armv7a-linux-gnueabihf.tar.gz", "18.1.8");
    assert k is not None;
    assert k.triple == "armv7a-linux-gnueabihf";
    assert k.ext == "tar.gz";
}

test "LLVM family Linux X64" {
    k = classify_asset("LLVM-22.1.8-Linux-X64.tar.xz", "22.1.8");
    assert k is not None;
    assert k.triple == "x86_64-linux";
    assert k.family == "LLVM";
}

test "LLVM family macOS ARM64" {
    k = classify_asset("LLVM-22.1.8-macOS-ARM64.tar.xz", "22.1.8");
    assert k is not None;
    assert k.triple == "aarch64-apple-darwin";
}

test "LLVM family Windows X64" {
    k = classify_asset("LLVM-19.1.7-Windows-X64.tar.xz", "19.1.7");
    assert k is not None;
    assert k.triple == "x86_64-pc-windows";
}

test "signature files rejected" {
    assert classify_asset("clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz.sig", "18.1.8") is None;
}

test "source tarballs rejected" {
    assert classify_asset("llvm-project-18.1.8.src.tar.xz", "18.1.8") is None;
    assert classify_asset("clang+llvm-18.1.8-foo.src.tar.xz", "18.1.8") is None;
}

test "windows installer exe rejected" {
    assert classify_asset("LLVM-22.1.8-win64.exe", "22.1.8") is None;
}

test "version mismatch rejected" {
    assert classify_asset("clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04.tar.xz", "18.1.8") is None;
}

test "non-tarball rejected" {
    assert classify_asset("README.txt", "18.1.8") is None;
}
