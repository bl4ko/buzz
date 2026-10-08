import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--secp256k1", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    dependency = (
        f".package(path: {json.dumps(str(args.secp256k1.resolve()))})"
        if args.secp256k1
        else '.package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", exact: "0.23.2")'
    )
    with tempfile.TemporaryDirectory(prefix="bl4uzz-watch-check-") as directory:
        package = Path(directory)
        sources = package / "Sources" / "WatchCheck"
        sources.mkdir(parents=True)
        tests = package / "Tests" / "WatchCheckTests"
        tests.mkdir(parents=True)
        for source in [
            root / "mobile/ios/Bl4uzzWatch/WatchRelay.swift",
            root / "mobile/ios/BuzzPushKit/Sources/BuzzPushKit/NostrHTTPAuth.swift",
        ]:
            shutil.copy2(source, sources / source.name)
        shutil.copy2(Path(__file__).with_name("WatchRelayTests.swift"), tests)
        signer_tests = root / "mobile/ios/BuzzPushKit/Tests/BuzzPushKitTests/NostrHTTPAuthTests.swift"
        (tests / signer_tests.name).write_text(
            signer_tests.read_text().replace("@testable import BuzzPushKit", "@testable import WatchCheck")
        )
        (package / "Package.swift").write_text(
            '// swift-tools-version:5.9\n'
            'import PackageDescription\n'
            'let package = Package(name: "WatchCheck", platforms: [.macOS(.v12)], '
            f'dependencies: [{dependency}], targets: ['
            '.target(name: "WatchCheck", dependencies: [.product(name: "P256K", package: "swift-secp256k1")]), '
            '.testTarget(name: "WatchCheckTests", dependencies: ["WatchCheck"])])\n'
        )
        subprocess.run(
            ["swift", "test", "--package-path", str(package), "--cache-path", str(package / "cache"), "--jobs", "2"],
            check=True,
        )


if __name__ == "__main__":
    main()
