
def test_user(host):
  user = host.user('particle')
  assert user.exists
  assert 'particle' in user.groups

def test_group(host):
  group = host.group('particle')
  assert group.exists

def test_id(host):
  id_result = host.run('id particle')
  assert id_result.succeeded
