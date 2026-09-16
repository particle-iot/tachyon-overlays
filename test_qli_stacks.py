"""QLI stack guard: no APT or optional desktop/application installers."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).parent

def read(path):
    return json.loads(re.sub(r'^\s*//.*$', '', path.read_text(), flags=re.M))

class QLIStacksTest(unittest.TestCase):
    def test_headless_stack_is_offline_and_complete(self):
        visited = []
        def visit(name):
            for step in read(ROOT / 'stacks' / (name + '.json'))['steps']:
                if step['type'] == 'stack':
                    visit(step['name'])
                else:
                    visited.append(step['name'])
                    overlay = ROOT / 'overlays' / step['name']
                    data = read(overlay / 'overlay.json')
                    for command in data['commands']:
                        text = command.get('cmd', '')
                        if command['type'].endswith('script'):
                            text += (overlay / command['script']).read_text()
                        self.assertIsNone(re.search(r'\b(?:apt|apt-get|dpkg|curl|wget)\b', text))
        visit('qli-headless-2.0')
        self.assertIn('qli-particle', visited)
        self.assertIn('qli-ssh', visited)
        self.assertEqual(visited[-1], 'set-headless-default-target')
