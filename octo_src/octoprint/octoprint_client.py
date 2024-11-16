import requests
import logging
import json

# 로거 설정
logger = logging.getLogger('mie_printer.octoprint')

class OctoPrintClient:
    def __init__(self, api_key, base_url="http://localhost:5000"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            'X-Api-Key': self.api_key,
            'Content-Type': 'application/json'
        }

    def get_printer_status(self):
        """프린터의 전체 상태 정보 조회"""
        try:
            # 프린터 상태 및 온도 정보 가져오기
            printer_response = requests.get(
                f"{self.base_url}/api/printer",
                headers=self.headers
            )
            
            # 작업 진행 상태 가져오기
            job_response = requests.get(
                f"{self.base_url}/api/job",
                headers=self.headers
            )
            
            if printer_response.status_code != 200 or job_response.status_code != 200:
                logger.error("Failed to get printer status")
                return None

            printer_data = printer_response.json()
            job_data = job_response.json()
            
            # 통합된 상태 정보 구성
            status_data = {
                "status": "idle",  # 기본값
                "temperature": {
                    "tool0": {
                        "actual": 0,
                        "target": 0
                    },
                    "bed": {
                        "actual": 0,
                        "target": 0
                    }
                },
                "progress": 0,
                "printing": False,
                "currentFile": None,
                "estimatedPrintTime": None,
                "timeLeft": None
            }
            
            # 온도 정보 업데이트
            if 'temperature' in printer_data:
                status_data["temperature"] = printer_data["temperature"]
            
            # 작업 상태 업데이트
            if job_data.get("state", "Offline") != "Offline":
                status_data["printing"] = job_data["state"] in ["Printing", "Pausing", "Paused"]
                status_data["status"] = job_data["state"].lower()
                
                if "progress" in job_data:
                    status_data["progress"] = job_data["progress"].get("completion", 0)
                    status_data["estimatedPrintTime"] = job_data["progress"].get("printTime", 0)
                    status_data["timeLeft"] = job_data["progress"].get("printTimeLeft", 0)
                
                if "file" in job_data:
                    status_data["currentFile"] = job_data["file"].get("name")

            return status_data

        except Exception as e:
            logger.error(f"Error getting printer status: {e}")
            return None

    def connect_printer(self, port=None, baudrate=115200):
        """프린터 연결"""
        try:
            data = {
                'command': 'connect',
                'port': port,
                'baudrate': baudrate,
                'printerProfile': '_default'
            }
            response = requests.post(
                f"{self.base_url}/api/connection",
                headers=self.headers,
                json=data
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error connecting to printer: {e}")
            return False

    def set_temperature(self, heater, target):
        """온도 설정 (tool0 또는 bed)"""
        try:
            data = {'command': 'target', 'target': target}
            response = requests.post(
                f"{self.base_url}/api/printer/{heater}/target",
                headers=self.headers,
                json=data
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error setting temperature: {e}")
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

    def check_connection(self):
        """프린터 연결 상태 확인"""
        try:
            response = requests.get(
                f"{self.base_url}/api/connection",
                headers=self.headers
            )
            if response.status_code == 200:
                return response.json()
            return None
        except Exception as e:
            logger.error(f"Error checking connection: {e}")
            return None

    def disconnect_printer(self):
        """프린터 연결 해제"""
        try:
            response = requests.post(
                f"{self.base_url}/api/connection",
                headers=self.headers,
                json={'command': 'disconnect'}
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error disconnecting printer: {e}")
            return False

    def pause_print(self):
        """출력 일시정지"""
        try:
            response = requests.post(
                f"{self.base_url}/api/job",
                headers=self.headers,
                json={'command': 'pause', 'action': 'pause'}
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error pausing print: {e}")
            return False

    def resume_print(self):
        """출력 재개"""
        try:
            response = requests.post(
                f"{self.base_url}/api/job",
                headers=self.headers,
                json={'command': 'pause', 'action': 'resume'}
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error resuming print: {e}")
            return False

    def cancel_print(self):
        """출력 취소"""
        try:
            response = requests.post(
                f"{self.base_url}/api/job",
                headers=self.headers,
                json={'command': 'cancel'}
            )
            return response.status_code == 204
        except Exception as e:
            logger.error(f"Error canceling print: {e}")
            return False