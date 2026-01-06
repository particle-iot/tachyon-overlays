def test_repo_installed(host):
    list_entry = host.file('/etc/apt/sources.list.d/particle.list')
    assert list_entry.exists

def test_apt_key_added(host):
    apt_key = host.file('/etc/apt/keyrings/particle-keyring.gpg')
    assert apt_key.exists
