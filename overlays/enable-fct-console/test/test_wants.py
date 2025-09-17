def test_adbd_ffbm(host):
    """
    Test if the adbd service is enabled and running
    """
    adbd = host.file("/etc/systemd/system/ffbm.target.wants/adbd.service")
    assert adbd.exists
    assert adbd.is_symlink

def test_serial_ffbm(host):
    """
    Test if the serial service is enabled and running
    """
    serial = host.file("/etc/systemd/system/ffbm.target.wants/serial-getty@ttyMSM0.service")
    assert serial.exists
    assert serial.is_symlink
