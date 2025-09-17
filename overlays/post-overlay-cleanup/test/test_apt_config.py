def test_nocofirm_removed(host):
    """
    Test that /etc/apt/apt.conf.d/90nocofirm is removed
    """
    nocofirm = host.file("/etc/apt/apt.conf.d/90nocofirm")
    assert nocofirm.exists is False

def test_proxies_removed(host):
    """
    Test that /etc/apt/apt.conf.d/95proxies is removed
    """
    proxiesfile = host.file("/etc/apt/apt.conf.d/95proxies")
    assert proxiesfile.exists is False

def test_debconf_frontend(host):
    """
    Test that Frontend is unset in /etc/debconf.conf
    """
    debconf = host.file("/etc/debconf.conf")
    assert debconf.exists is True
    assert "Frontend: Noninteractive" not in debconf.content_string
    