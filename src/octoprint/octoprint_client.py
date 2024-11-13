import requests
import logging

logger = logging.getLogger(__name__)

class OctoPrintClient:
    def __init__(self, api_key, base_url="http://localhost"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            'X-Api-Key': self.api_key,
            'Content-Type': 'application/json'
        }

    def get_printer_status(self):
        """프린터 상태 조회"""
        try:
            response = requests.get(
                f"{self.base_url}/api/printer",
                headers=self.headers
            )
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Failed to get printer status: {response.status_code}")
                return None
        except Exception as e:
            logger.error(f"Error getting printer status: {e}")
            return None

    def upload_file(self, filename, file_data):
        """G-code 파일 업로드"""
        try:
            files = {'file': (filename, file_data)}
            response = requests.post(
                f"{self.base_url}/api/files/local",
                headers={'X-Api-Key': self.api_key},
                files=files
            )
            return response.status_code == 201
        except Exception as e:
            logger.error(f"Error uploading file: {e}")
            return False

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