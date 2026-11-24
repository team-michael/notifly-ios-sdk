#!/usr/bin/env python3
"""Test the production module across isolated iOS simulator app processes.

Usage: python3 scripts/test_shared_identity_keychain.py <booted-simulator-udid>
Only synthetic records in a dedicated test access group are created/deleted.
"""
import json
import platform
import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/shared-identity-probe"
SOURCE_ROOT = ROOT / "Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes"
SOURCES = [SOURCE_ROOT / "Shared/KeychainProcessing.swift", SOURCE_ROOT / "Shared/Keychain.swift",
           SOURCE_ROOT / "NotiflyUtil/SharedIdentityStore.swift",
           SOURCE_ROOT / "NotiflyUtil/LegacyIdentityStore.swift"]
MAIN = ROOT / "Tests/SharedIdentityStoreProbe/main.swift"
GROUP = "group.notifly.keychain-module-test"


def run(*args):
    return subprocess.check_output(args, text=True, timeout=90).strip()


def main():
    device = sys.argv[1]
    OUT.mkdir(parents=True, exist_ok=True)
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    project = "keychain-probe-" + str(uuid.uuid4())
    apps = {}
    observations = []
    try:
        for role in ("writer", "reader", "unentitled"):
            bundle = "tech.notifly.sharedidentityprobe." + role
            app = OUT / (role + ".app")
            app.mkdir(exist_ok=True)
            entitlements = {
                "application-identifier": "TESTTEAM01." + bundle,
                "com.apple.developer.team-identifier": "TESTTEAM01",
                "get-task-allow": True,
            }
            if role != "unentitled":
                entitlements["com.apple.security.application-groups"] = [GROUP]
            ent_path = OUT / (role + ".entitlements")
            ent_path.write_bytes(plistlib.dumps(entitlements))
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": bundle, "CFBundleExecutable": "Probe",
                "CFBundleName": role, "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                "MinimumOSVersion": "15.0", "UIDeviceFamily": [1, 2],
                "UILaunchScreen": {}, "LSRequiresIPhoneOS": True,
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            }))
            run("xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-sdk", sdk,
                "-target", arch + "-apple-ios15.0-simulator", "-framework", "Security",
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__entitlements",
                "-Xlinker", str(ent_path), *map(str, SOURCES), str(MAIN), "-o", str(app / "Probe"))
            # Simulator entitlements belong in the Mach-O section, not the macOS ad-hoc signature.
            run("codesign", "--force", "--sign", "-", str(app))
            run("xcrun", "simctl", "install", device, str(app))
            apps[role] = bundle

        def check(role, action, expected, project_id=project):
            container = Path(run("xcrun", "simctl", "get_app_container", device, apps[role], "data"))
            result_path = container / "Documents/result.json"
            result_path.unlink(missing_ok=True)
            launch = subprocess.run(
                ["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                 device, apps[role], action, project_id],
                capture_output=True, text=True, timeout=90
            )
            # A fast-exiting fixture can finish before simctl obtains its process handle.
            # Only accept this specific race if this launch produced a fresh atomic result;
            # the expected Keychain status and values are still checked below.
            completed_before_handle = (
                launch.returncode == 3
                and "did not return a process handle nor launch error" in launch.stderr
                and result_path.is_file()
            )
            if completed_before_handle:
                print(f"simctl missed process handle for {role}/{action}; validating fresh result")
            elif launch.returncode != 0:
                print(launch.stderr, file=sys.stderr)
                launch.check_returncode()
            result = json.loads(result_path.read_text())
            assert all(result.get(k) == v for k, v in expected.items()), (role, action, result, expected)
            observations.append({"role": role, "action": action, "result": result})

        check("writer", "write", {"status": 0})
        check("reader", "read", {"status": 0, "found": True, "deviceId": "synthetic-device", "externalUserId": "synthetic-user"})
        check("reader", "attributes", {"status": 0, "accessible": "cku", "accessGroup": GROUP, "synchronizable": False})
        check("unentitled", "read", {"status": -34018})
        check("unentitled", "write", {"status": -34018})
        check("reader", "read", {"status": 0, "found": False}, project + "-other")
        check("reader", "logout", {"status": 0})
        check("writer", "read", {"status": 0, "found": True, "deviceId": "synthetic-device", "externalUserId": ""})
        check("writer", "delete", {"status": 0})
        check("reader", "read", {"status": 0, "found": False})
        migration_project = project + "-migration"
        check("writer", "seed-legacy", {"seeded": True}, migration_project)
        check("reader", "read-migrated", {"deviceId": "legacy-device", "externalUserId": "legacy-user", "legacyPresent": True}, migration_project)
        check("writer", "migrate", {"deviceId": "legacy-device", "externalUserId": "legacy-user", "legacyPresent": False}, migration_project)
        check("reader", "read-migrated", {"deviceId": "legacy-device", "externalUserId": "legacy-user", "legacyPresent": False}, migration_project)
        check("writer", "migrate", {"deviceId": "legacy-device", "externalUserId": "legacy-user", "legacyPresent": False}, migration_project)
        check("writer", "logout-migrated", {"deviceId": "legacy-device", "externalUserId": "", "legacyPresent": False}, migration_project)
        check("reader", "read-migrated", {"deviceId": "legacy-device", "externalUserId": "", "legacyPresent": False}, migration_project)
        check("writer", "delete", {"status": 0}, migration_project)
        (OUT / "results.json").write_text(json.dumps(observations, indent=2) + "\n")
        print(f"PASS: {len(observations)} cross-process Keychain checks; {OUT / 'results.json'}")
    finally:
        # Restrict cleanup to this run's unique record and these dedicated fixture apps.
        if "writer" in apps:
            for cleanup_project in [project, project + "-migration"]:
                subprocess.run(["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, apps["writer"], "delete", cleanup_project], capture_output=True, timeout=30)
        for bundle in apps.values():
            subprocess.run(["xcrun", "simctl", "uninstall", device, bundle], capture_output=True)


if __name__ == "__main__":
    main()
