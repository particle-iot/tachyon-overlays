def test_package_installation_network_manager(host):
    package = host.package("network-manager")
    assert package.is_installed, "Network Manager package should be installed"
    assert "particle" in package.version, "Network Manager package version should contain 'particle'"

def test_package_installation_netplan(host):
    package = host.package("netplan.io")
    assert package.is_installed, "Netplan package should be installed"
    assert "particle" in package.version, "Netplan package version should contain 'particle'"
