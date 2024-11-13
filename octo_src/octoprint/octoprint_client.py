class OctoPrintClient:
    def __init__(self, api_key, base_url="http://localhost:5000"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            'X-Api-Key': self.api_key,
            'Content-Type': 'application/json'
        }

    def get_printer_status(self):
        """프린터 상태 및 온도 정보 조회"""
        try:
            response = requests.get(
                f"{self.base_url}/api/printer",
                headers=self.headers
            )
            return response.json() if response.status_code == 200 else None
        except Exception as e:
            logger.error(f"Error getting printer status: {e}")
            return None

    def start_print(self, filename):
        """출력 시작"""
        try:
            response = requests.post(
                f"{self.base_url}/api/files/local/{filename}",
                headers=self.headers,
                json={'command': 'select', 'print': True}
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Error starting print: {e}")
            return False

    def set_temperature(self, heater, target):
        """온도 설정 (tool0 또는 bed)"""
        try:
            data = {'command': 'target', 'target': target}
            response = requests.post(
                f"{self.base_url}/api/printer/{heater}",
                headers=self.headers,
                json=data
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error setting temperature: {e}")
            return False 