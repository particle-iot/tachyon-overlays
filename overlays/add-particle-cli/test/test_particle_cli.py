def test_particle_cli(host):
    cmd = host.run('/root/bin/particle version --no-update-check')
    assert cmd.rc == 0

