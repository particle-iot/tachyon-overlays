import pytest
import json

DISTRO_VERSION_PATH = '/etc/particle/distro_versions.json'

def test_distroversions_exists(host):
  version_file = host.file(DISTRO_VERSION_PATH)
  assert version_file.exists

def test_distroversions_valid_json(host):
  version_file = host.file(DISTRO_VERSION_PATH)
  values = json.loads(version_file.content_string)
  assert 'distro' in values
  assert 'version' in values['distro']


def test_distroversions_board(host, dut):
  version_file = host.file(DISTRO_VERSION_PATH)
  values = json.loads(version_file.content_string)
  assert 'board' in values['distro']
  assert values['distro']['board'] == dut["board"] # The hil tests currently only run on a formfactor board
