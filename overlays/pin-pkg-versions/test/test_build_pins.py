import json
import os

def test_all_packages_pinned(host):
    """
    Test that each package listed in versions.json is installed and matches the expected version.
    """
    # Load versions.json from 3 directories up
    base_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
    versions_json_path = os.path.join(base_path, "versions.json")
    with open(versions_json_path, "r") as f:
        version_data = json.load(f)

    packages = version_data.get("packages", {})
    assert packages, "No 'packages' found in versions.json"

    is_headless = host.run("jq -e '.distro.variant == \"headless\"' /etc/particle/distro_versions.json").succeeded

    failures = []
    for package_name, expected_version in packages.items():
        if is_headless and package_name == "particle-tachyon-desktop-setup":
            continue
        
        pkg = host.package(package_name)
        if not pkg.is_installed:
            failures.append(f"{package_name} is not installed")
        elif pkg.version != expected_version:
            failures.append(f"{package_name} version is {pkg.version}, expected {expected_version}")

    assert not failures, "Package pinning failures:\n" + "\n".join(failures)

