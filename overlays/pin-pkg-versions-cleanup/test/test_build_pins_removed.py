def test_build_pins_file_removed(host):
    """
    Test that the build-pins.pref file is removed after cleanup.
    """
    build_pins_file = host.file("/etc/apt/preferences.d/build-pins.pref")
    assert not build_pins_file.exists, "build-pins.pref file should be removed after cleanup"
