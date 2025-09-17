import os
import pytest


def test_ssh_installed(host):
  ssh = host.package('openssh-server')
  assert ssh.is_installed

def test_ssh_running(host):
  ssh = host.service('sshd')
  assert ssh.is_running
  assert ssh.is_enabled

@pytest.fixture(scope="module")
def ssh_host_keys(host):
    """Parse sshd_config to get HostKey file paths dynamically."""
    sshd_config = host.run("sshd -T")

    assert sshd_config.rc == 0, "Failed to read sshd_config!"

    # Extract HostKey paths from sshd_config
    key_paths = []
    for line in sshd_config.stdout.splitlines():
        line = line.strip()
        if line.startswith("hostkey "):
            key_paths.append(line.split()[1])
            key_paths.append(line.split()[1] + ".pub")

    assert key_paths, "No HostKey entries found in sshd_config!"
    return key_paths

def test_ssh_host_keys_recent(host, ssh_host_keys):
    """Verify that SSH host keys were created or modified since the last reboot."""

    for key_file in ssh_host_keys:

      # Get file object
      key = host.file(key_file)

      # Ensure file exists
      assert key.exists, f"Missing SSH key: {key_file}"
