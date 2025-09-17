def test_resolv_conf(host):
    """
    Test that /etc/resolv.conf is a symlink to /run/systemd/resolve/stub-resolv.conf
    """
    resolv_conf = host.file("/etc/resolv.conf")
    assert resolv_conf.is_symlink
    assert resolv_conf.linked_to == "/run/systemd/resolve/stub-resolv.conf"
