import pytest
import json
import re


# Values asserted in tests are for the hil rig

def split_result(output):
  # Remove leading/trailing whitespace and split into lines
  # Unpack so that `body` is all lines except the last, and `status` is the final line
  *body, status = output.strip().splitlines()
  return body, status


def assert_pass_and_contains(output, text):
  # Use split_result to separate test output into body and status
  body, status = split_result(output)
  # Verify the final line is exactly 'PASS'
  assert status == 'PASS'
  # Verify the expected text appears somewhere in the body
  assert any(text in line for line in body)


@pytest.mark.fct
def test_hello(send_command):
  result = send_command("echo Hello")
  assert result.strip() == "Hello"


@pytest.mark.fct
def test_device_id(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-device-id.sh"""),
    f"device_id = {dut['device_id']}"
  )


@pytest.mark.fct
def test_read_distro_versions(send_command):
  output = send_command("""/opt/particle/tests/read-distro-versions.sh""")
  body, status = split_result(output)
  assert status == 'PASS'

  json_line = next(
    (line.split(" = ", 1)[1] for line in body if line.startswith("distro_versions = ")),
    None
  )
  assert json_line is not None, "JSON output not found"

  parsed_json = json.loads(json_line)
  assert isinstance(parsed_json, dict)
  assert parsed_json, "JSON object is empty"

  distro = parsed_json.get("distro", {})
  version = distro.get("version")
  assert version is not None, "`distro.version` key missing"

  semver_re = re.compile(
    r'^\d+\.\d+\.\d+'
    r'(?:-[0-9A-Za-z.-]+)?'
    r'(?:\+[0-9A-Za-z.-]+)?$'
  )
  assert semver_re.match(version), f"`distro.version` '{version}' is not valid semver"


@pytest.mark.fct
def test_read_eid(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-eid.sh"""),
    f"eid = {dut['eid']}"
  )


@pytest.mark.fct
def test_read_storage(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-storage.sh"""),
    f"storage = {dut['storage']}"
  )


@pytest.mark.fct
def test_read_memory(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-memory.sh"""),
    f"memory = {dut['memory']}"
  )


@pytest.mark.fct
def test_read_modem_firmware(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-modem-firmware.sh"""),
    f"modem_firmware = {dut['modem_firmware']}"
  )


@pytest.mark.fct
def test_read_modem_manufacturer(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-modem-manufacturer.sh"""),
    f"modem_manufacturer = {dut['modem_manufacturer']}"
  )


@pytest.mark.fct
def test_read_modem_model(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-modem-model.sh"""),
    f"modem_model = {dut['modem_model']}"
  )


@pytest.mark.fct
def test_read_modem_serial(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-modem-serial.sh"""),
    f"modem_serial = {dut['modem_serial']}"
  )


@pytest.mark.fct
def test_read_region(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-region.sh"""),
    f"region = {dut['region']}"
  )


@pytest.mark.fct
def test_wifi_setup(send_command):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/setup-wifi.sh"""),
    "WIFI SETUP COMPLETE"
  )


@pytest.mark.fct
def test_wifi_exists(send_command):
  # check that the wlan0 interface directory exists
  body, status = split_result(send_command('[ -d /sys/class/net/wlan0 ] && echo PASS || echo FAIL'))
  assert status == 'PASS'


@pytest.mark.fct
def test_wifi_teardown(send_command):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/teardown-wifi.sh"""),
    "WIFI TEARDOWN COMPLETE"
  )


@pytest.mark.fct
def test_gnss_command(send_command):
  send_command("""systemctl start qlrild.service""")
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/test-gnss.sh --sleep 6 --skip-validate"""),
    "GNSS signal scan complete, validation skipped"
  )


@pytest.mark.fct
def test_wifi_mac(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-wifi-mac.sh"""),
    f"wifi_mac = {dut['wifi_mac']}"
  )


@pytest.mark.fct
def test_bluetooth_mac(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-bluetooth-mac.sh"""),
    f"bluetooth_mac = {dut['bluetooth_mac']}"
  )


@pytest.mark.fct
def test_imei_1(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-imei-1.sh"""),
    f"imei_1 = {dut['imei_1']}"
  )


@pytest.mark.fct
def test_imei_2(send_command, dut):
  assert_pass_and_contains(
    send_command("""/opt/particle/tests/read-imei-2.sh"""),
    f"imei_2 = {dut['imei_2']}"
  )
