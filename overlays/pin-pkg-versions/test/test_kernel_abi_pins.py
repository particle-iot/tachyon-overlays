"""
Unit tests for expand_kernel_abi_pins (no hardware, no chroot).

Run with:  python3 -m pytest overlays/pin-pkg-versions/test/test_kernel_abi_pins.py
"""
import importlib.util
import os

_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "pin-pkg-versions.py")


def _load():
    spec = importlib.util.spec_from_file_location("pin_pkg_versions", _SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_expands_the_three_abi_packages():
    m = _load()
    pkgs = {"linux-particle": "6.8.0-1058.59+particle10"}
    added = m.expand_kernel_abi_pins(pkgs)
    assert added == 3
    for stem in ("image", "modules", "headers"):
        name = f"linux-{stem}-6.8.0-1058-particle"
        assert pkgs[name] == "6.8.0-1058.59+particle10", name


def test_tracks_a_different_abi():
    m = _load()
    pkgs = {"linux-particle": "6.8.0-1056.57+particle6"}
    m.expand_kernel_abi_pins(pkgs)
    assert "linux-image-6.8.0-1056-particle" in pkgs
    assert "linux-image-6.8.0-1058-particle" not in pkgs


def test_noop_without_a_kernel_pin():
    m = _load()
    pkgs = {"particle-linux": "0.25.2-1"}
    assert m.expand_kernel_abi_pins(pkgs) == 0
    assert pkgs == {"particle-linux": "0.25.2-1"}


def test_noop_on_an_unrecognised_version_scheme():
    m = _load()
    pkgs = {"linux-particle": "weird-version"}
    assert m.expand_kernel_abi_pins(pkgs) == 0
    assert list(pkgs) == ["linux-particle"]


def test_does_not_clobber_an_explicit_pin():
    m = _load()
    pkgs = {
        "linux-particle": "6.8.0-1058.59+particle10",
        "linux-image-6.8.0-1058-particle": "6.8.0-1058.59+particle9",
    }
    m.expand_kernel_abi_pins(pkgs)
    assert pkgs["linux-image-6.8.0-1058-particle"] == "6.8.0-1058.59+particle9"


def test_generated_pin_file_contains_the_abi_packages():
    m = _load()
    pkgs = {"linux-particle": "6.8.0-1058.59+particle10"}
    m.expand_kernel_abi_pins(pkgs)
    content = m.generate_pin_content(pkgs, 900)
    assert "Package: linux-image-6.8.0-1058-particle" in content
    assert "Pin: version 6.8.0-1058.59+particle10" in content
    assert "Pin-Priority: 900" in content
