
def test_service_running(host):
    service = host.service('docker')
    assert service.is_running
    assert service.is_enabled

def test_docker_ps(host):
    cmd = host.run('docker ps')
    assert cmd.rc == 0

def test_docker_hello_world(host):
    cmd = host.run('docker run --rm hello-world')
    assert cmd.rc == 0
