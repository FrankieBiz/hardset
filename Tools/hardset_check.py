#!/usr/bin/env python3
"""Run honest Linux checks from exact copies of a Hardset checkout."""

import argparse
import ctypes.util
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Reuse the installed, pinned Swift toolchain and official SQLite UUID support;
# source selection and test coverage are versioned with the repository.
TOOLING = Path(os.environ.get("HARDSET_TOOLING_ROOT", Path.home() / ".local/share/hardset-tooling"))
# These suites require the Apple-only Database/SyncSetup implementations.
# Every other Store test is selected automatically, including future additions.
APPLE_STORE_TESTS = frozenset({
    "SchemaTests.swift", "SyncDelegateTests.swift", "SyncEngineRetentionTests.swift",
    "AccountChangePolicyTests.swift",
})
CONCURRENCY = '''let concurrency: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]
let isolated: [SwiftSetting] = concurrency + [.defaultIsolation(MainActor.self)]
'''


class CheckError(Exception):
    pass


def repository(path):
    path = path.expanduser().resolve()
    for candidate in (path, *path.parents):
        package = candidate / "Packages/HardsetKit"
        if (package / "Sources/HardsetCore").is_dir():
            return candidate, package
    raise CheckError(f"No Hardset checkout found at or above {path}; supply --repo.")


def swift_tools(requested):
    executable = Path(requested).expanduser() if requested else (
        TOOLING / "swift-6.2.4-RELEASE-fedora41/usr/bin/swift"
    )
    if not executable.is_file():
        fallback = shutil.which("swift")
        if requested or not fallback:
            raise CheckError(f"Swift is unavailable at {executable}; supply --swift.")
        executable = Path(fallback)
    # Swift's driver selects its mode from argv[0]; resolving the swift symlink
    # to swift-driver would discard that mode and break even --version.
    executable = executable.absolute()
    result = subprocess.run([str(executable), "--version"], check=False, capture_output=True, text=True)
    match = re.search(r"Swift version (\d+)\.(\d+)", result.stdout)
    if result.returncode or not match or tuple(map(int, match.groups())) < (6, 2):
        raise CheckError("These checks require a working Swift 6.2 or newer toolchain.")
    compiler = executable.parent / "swiftc"
    if not compiler.exists():
        raise CheckError(f"Swift compiler missing: {compiler}")
    return executable, compiler


def copy_exact(source, destination, excluded=()):
    """Preserve unchanged file timestamps so subsequent checks reuse compilation."""
    if not source.is_dir():
        raise CheckError(f"Source directory missing: {source}")
    destination.mkdir(parents=True, exist_ok=True)
    source_files = {
        item.relative_to(source): item for item in source.rglob("*.swift")
        if item.relative_to(source).as_posix() not in excluded
    }
    for old in destination.rglob("*.swift"):
        if old.relative_to(destination) not in source_files:
            old.unlink()
    for name, item in source_files.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != item.read_bytes():
            # Changed contents must get a fresh timestamp even when a generator
            # or checkout preserved the original file's old timestamp.
            shutil.copyfile(item, target)


def write_if_changed(path, contents):
    if not path.exists() or path.read_text() != contents:
        path.write_text(contents)


def run_logged(command, cwd, environment, log, title):
    print(f"{title}…", flush=True)
    with log.open("w") as output:
        result = subprocess.run(command, check=False, cwd=cwd, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    lines = log.read_text(errors="replace").splitlines()
    for line in lines:
        if "Build complete!" in line:
            print(line, flush=True)
        summary = re.search(r"Test run with (\d+) tests?(?: in (\d+) suites?)? (passed|failed)\b", line)
        if summary:
            tests, suites, status = summary.groups()
            scope = f"{tests} tests" + (f" in {suites} suites" if suites is not None else "")
            print(f"Swift Testing: {scope} {status}", flush=True)
    if result.returncode:
        print("\n".join(lines[-35:]), file=sys.stderr)
        raise CheckError(f"{title} failed (exit {result.returncode}); full output: {log}")
    print(f"Output: {log}", flush=True)


def parse(repo, compiler, cache):
    if not shutil.which("rg"):
        raise CheckError("Syntax checks need ripgrep (rg).")
    files = subprocess.check_output([
        "rg", "--files", "--hidden", "-g", "*.swift", "-g", "!.git/**",
        "-g", "!**/.build/**", "-g", "!**/DerivedData/**",
    ], cwd=repo, text=True).splitlines()
    errors = []
    for filename in files:
        result = subprocess.run([str(compiler), "-frontend", "-parse", str(repo / filename)],
                                check=False, capture_output=True, text=True)
        if result.returncode:
            errors.append(result.stderr)
    log = cache / "parse.log"
    log.write_text("\n".join(errors) or f"Parsed {len(files)} Swift files; failures: 0\n")
    print(f"Syntax only: parsed {len(files)} Swift files; failures: {len(errors)}", flush=True)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise CheckError(f"Swift syntax failed; full output: {log}")


def package_manifest(kind, pins):
    dependencies = ""
    targets = '.target(name: "HardsetCore", swiftSettings: concurrency)'
    if kind == "core":
        targets += ',\n    .testTarget(name: "HardsetCoreTests", dependencies: ["HardsetCore"], swiftSettings: concurrency)'
    else:
        entries = []
        for identity in ("sqlite-data", "grdb.swift"):
            pin = pins[identity]
            state = pin["state"]
            requirement = f'exact: "{state["version"]}"' if "version" in state else f'revision: "{state["revision"]}"'
            entries.append(f'.package(url: "{pin["location"]}", {requirement})')
        dependencies = "dependencies: [" + ", ".join(entries) + "],"
        targets += ''',
    .target(name: "HardsetStore", dependencies: ["HardsetCore", .product(name: "SQLiteData", package: "sqlite-data")], swiftSettings: isolated),
    .testTarget(name: "HardsetStoreTests", dependencies: ["HardsetStore", "HardsetCore", .product(name: "GRDB", package: "GRDB.swift")], swiftSettings: concurrency)'''
    return f'''// swift-tools-version: 6.2
import PackageDescription
{CONCURRENCY}
let package = Package(name: "Hardset{kind.title()}PortableCheck", {dependencies}
  targets: [
    {targets}
  ]
)
'''


def verify_pins(workspace, original):
    actual = {pin["identity"]: pin for pin in json.loads((workspace / "Package.resolved").read_text())["pins"]}
    for identity, expected in original.items():
        if identity not in actual or actual[identity]["state"] != expected["state"]:
            raise CheckError(f"Portable dependency {identity} differs from the repository pin; no tests claimed. Use --refresh-dependencies.")


def sqlite_support():
    support = TOOLING / "sqlite-support"
    if not ctypes.util.find_library("sqlite3"):
        raise CheckError("SQLite runtime missing. Fedora package: sqlite-libs.")
    compiler = shutil.which("gcc")
    if not compiler:
        raise CheckError("SQLite UUID support needs a C compiler. Fedora package: gcc.")
    library = support / "uuid_setup.so"
    inputs = [support / name for name in ("uuid.c", "auto_uuid.c", "sqlite3.h", "sqlite3ext.h")]
    if any(not item.exists() for item in inputs):
        raise CheckError(f"Official SQLite support sources missing from {support}.")
    if not library.exists() or any(item.stat().st_mtime > library.stat().st_mtime for item in inputs):
        result = subprocess.run([
            compiler, "-shared", "-fPIC", f"-I{support}", str(support / "uuid.c"),
            str(support / "auto_uuid.c"), "-Wl,-l:libsqlite3.so.0", "-o", str(library),
        ], check=False, capture_output=True, text=True)
        if result.returncode:
            raise CheckError(f"Could not compile official SQLite UUID support:\n{result.stderr}")
    # Development packages normally supply this name; the runtime library is enough here.
    runtime = next((Path(directory) / "libsqlite3.so.0" for directory in
                    ("/lib64", "/usr/lib64", "/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu")
                    if (Path(directory) / "libsqlite3.so.0").exists()), None)
    if runtime is None:
        raise CheckError("Cannot locate SQLite runtime; install sqlite-devel or inspect sqlite-support.")
    link = support / "libsqlite3.so"
    if not link.exists() or link.resolve() != runtime.resolve():
        link.unlink(missing_ok=True)
        link.symlink_to(runtime)
    return support, library


def test(kind, package, swift, cache, shared, refresh):
    workspace = cache / kind
    workspace.mkdir(parents=True, exist_ok=True)
    copy_exact(package / "Sources/HardsetCore", workspace / "Sources/HardsetCore")
    pins = {}
    original_bytes = b""
    if kind == "core":
        copy_exact(package / "Tests/HardsetCoreTests", workspace / "Tests/HardsetCoreTests")
    else:
        original_bytes = (package / "Package.resolved").read_bytes()
        pins = {pin["identity"]: pin for pin in json.loads(original_bytes)["pins"]}
        if not {"sqlite-data", "grdb.swift"} <= pins.keys():
            raise CheckError("Package.resolved must pin SQLiteData and GRDB.")
        copy_exact(package / "Sources/HardsetStore", workspace / "Sources/HardsetStore",
                   excluded=("Database.swift", "SyncSetup.swift"))
        tests = package / "Tests/HardsetStoreTests"
        selected = {item.name for item in tests.glob("*.swift")} - APPLE_STORE_TESTS
        if not selected:
            raise CheckError("No portable Store test files found.")
        test_files = tuple(tests.rglob("*.swift"))
        excluded = tuple(item.relative_to(tests).as_posix() for item in test_files
                         if item.name not in selected)
        portable_tests = workspace / "Tests/HardsetStoreTests"
        copy_exact(tests, portable_tests, excluded=excluded)
        print(f"Store coverage: {len(tuple(portable_tests.rglob('*.swift')))} portable Store files "
              f"of {len(test_files)}; Apple-only exclusions: {', '.join(sorted(APPLE_STORE_TESTS))}", flush=True)
    write_if_changed(workspace / "Package.swift", package_manifest(kind, pins))
    environment = os.environ.copy()
    environment["XDG_CACHE_HOME"] = str(shared / "xdg")
    environment["CLANG_MODULE_CACHE_PATH"] = str(shared / "clang")
    options = ["--disable-sandbox", "--scratch-path", str(workspace / ".build"),
               "--cache-path", str(shared / "swiftpm"), "--config-path", str(shared / "config"),
               "--security-path", str(shared / "security")]
    compiler_options = []
    if kind == "store":
        support, library = sqlite_support()
        environment["LD_PRELOAD"] = str(library) + (":" + environment["LD_PRELOAD"] if environment.get("LD_PRELOAD") else "")
        compiler_options = ["-Xcc", f"-I{support}", "-Xswiftc", f"-L{support}"]
        digest = hashlib.sha256(original_bytes + (workspace / "Package.swift").read_bytes()).hexdigest()
        stamp = workspace / "repository-pins.sha256"
        if refresh or not stamp.exists() or stamp.read_text() != digest or not (workspace / "Package.resolved").exists():
            (workspace / "Package.resolved").write_bytes(original_bytes)
            run_logged([str(swift), "package", "resolve", *options], workspace, environment,
                       cache / "resolve.log", "Resolving original pinned Store dependencies")
            verify_pins(workspace, pins)
            stamp.write_text(digest)
        verify_pins(workspace, pins)
        options += ["--force-resolved-versions"]
        print("Store scope: all portable suites; CloudKit wiring excluded; official SQLite UUID extension loaded.", flush=True)
    run_logged([str(swift), "test", *options, *compiler_options], workspace, environment,
               cache / f"{kind}.log", f"Running {kind.title()} tests")


def main():
    parser = argparse.ArgumentParser(prog="hardset-check", description="Linux subset checks for Hardset; this is not an iOS build.",
        epilog="core: all Core tests. store: all portable Store tests. parse: syntax only. all: every check. SwiftUI, Charts, CloudKit, AlarmKit, widgets and device behavior require Xcode/iOS verification.")
    parser.add_argument("command", choices=("core", "store", "parse", "all"))
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Checkout path (default: current directory; searches parents)")
    parser.add_argument("--cache-dir", type=Path, help="Cache root (default: XDG_CACHE_HOME/hardset-check)")
    parser.add_argument("--swift", help="Swift executable override")
    parser.add_argument("--refresh-dependencies", action="store_true", help="Re-resolve temporary Store package from original repository pins")
    args = parser.parse_args()
    try:
        repo, package = repository(args.repo)
        swift, compiler = swift_tools(args.swift)
        user_cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
        cache_root = (args.cache_dir or user_cache / "hardset-check").expanduser().resolve()
        identity = hashlib.sha256(str(repo).encode()).hexdigest()[:12]
        cache = cache_root / "workspaces" / identity
        shared = cache_root / "shared"
        cache.mkdir(parents=True, exist_ok=True)
        shared.mkdir(parents=True, exist_ok=True)
        print(f"Repository: {repo}\nLinux checks: native iOS frameworks and device behavior are outside this command.", flush=True)
        with (cache / "check.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise CheckError("Another hardset-check is running for this checkout.")
            if args.command in ("parse", "all"):
                parse(repo, compiler, cache)
            if args.command in ("core", "all"):
                test("core", package, swift, cache, shared, args.refresh_dependencies)
            if args.command in ("store", "all"):
                test("store", package, swift, cache, shared, args.refresh_dependencies)
        return 0
    except (CheckError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"hardset-check: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
