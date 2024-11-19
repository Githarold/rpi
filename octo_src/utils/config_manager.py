import json
from pathlib import Path

class ConfigManager:
    def __init__(self, config_file='config/config.json'):
        self.config_file = Path(config_file)
        self.config = self.load_config()

    def load_config(self):
        if not self.config_file.exists():
            self.config_file.parent.mkdir(parents=True, exist_ok=True)
            default_config = {
                'octoprint': {
                    'api_key': 'Nie_leXdutAe3YfbeVkf0TjyTgSpmfGbSFMrNfQFqSs',
                    'base_url': 'http://localhost:5000'
                },
                'bluetooth': {
                    'uuid': '00001101-0000-1000-8000-00805F9B34FB',
                    'service_name': 'SCARA 3D Printer'
                },
                'upload': {
                    'folder': '/home/c9lee/.octoprint/uploads'
                }
            }
            self.save_config(default_config)
            return default_config
            
        with open(self.config_file, 'r') as f:
            return json.load(f)

    def save_config(self, config):
        with open(self.config_file, 'w') as f:
            json.dump(config, f, indent=4)

    def get(self, key, default=None):
        keys = key.split('.')
        value = self.config
        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default 