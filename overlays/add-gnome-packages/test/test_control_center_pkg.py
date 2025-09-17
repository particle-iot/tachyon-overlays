def test_package_installation_gnome_control_center(host):
    package = host.package("gnome-control-center")
    assert package.is_installed, "Gnome Control Center package should be installed"
    assert "particle" in package.version, "Gnome Control Center package version should contain 'particle'"
