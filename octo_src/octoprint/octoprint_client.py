import requests
import logging
import json

# 로거 설정
logger = logging.getLogger('mie_printer.octoprint')

class OctoPrintClient:
    def __init__(self, api_key, base_url="http://localhost:5000", timeout=10):
        self.api_key = api_key
        self.base_url = base_url
        self.timeout = timeout
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
            
            # 디버깅을 위한 로그 추가
            logger.debug(f"Printer API Response: {json.dumps(printer_data, indent=2)}")
            logger.debug(f"Job API Response: {json.dumps(job_data, indent=2)}")
            
            # 통합된 상태 정보 구성
            status_data = {
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
                "fan_speed": 0,  # 팬 속도 추가
                "progress": 0,
                "currentFile": None,
                "timeLeft": 0,
                "currentLayer": 0,
                "totalLayers": 0
            }
            
            # 온도 정보 업데이트
            if 'temperature' in printer_data:
                status_data["temperature"] = printer_data["temperature"]
            
            # 팬 속도 업데이트 (0-255 값을 퍼센트로 변환)
            if 'state' in printer_data and 'flags' in printer_data['state']:
                if 'fan' in printer_data['state']:
                    fan_speed = printer_data['state']['fan'].get('speed', 0)
                    status_data["fan_speed"] = round((fan_speed / 255) * 100)
            
            # 작업 상태 업데이트
            if job_data.get("state", "Offline") != "Offline":
                if "progress" in job_data:
                    status_data["progress"] = job_data["progress"].get("completion", 0)
                    status_data["timeLeft"] = job_data["progress"].get("printTimeLeft", 0)
                
                if "file" in job_data:
                    status_data["currentFile"] = job_data["file"].get("name")
                    
                    # 레이어 정보 업데이트
                    metadata = job_data["file"].get("metadata", {})
                    # 디버깅을 위한 로그 추가
                    logger.debug(f"File metadata: {json.dumps(metadata, indent=2)}")
                    logger.debug(f"Progress data: {json.dumps(job_data.get('progress', {}), indent=2)}")
                    
                    status_data["totalLayers"] = metadata.get("layerCount", 0)
                    status_data["currentLayer"] = job_data.get("progress", {}).get("currentLayer", 0)

            logger.debug(f"Final status data: {json.dumps(status_data, indent=2)}")
            return status_data

        except Exception as e:
            logger.error(f"Error getting printer status: {e}")
            return None

    def connect_printer(self, port=None, baudrate=250000):
        """프린터 연결"""
        try:
            # 포트가 지정되지 않은 경우 자동 검색
            if port is None:
                possible_ports = ['VIRTUAL', '/dev/ttyACM0', '/dev/ttyUSB0']
                # possible_ports = ['/dev/ttyACM0', '/dev/ttyUSB0']
                connection_status = self.check_connection()
                if connection_status:
                    available_ports = connection_status.get('options', {}).get('ports', [])
                    for p in possible_ports:
                        if p in available_ports:
                            port = p
                            break
            
            if port is None:
                port = '/dev/ttyACM0'  # 기본값
            
            data = {
                'command': 'connect',
                'port': port,
                'baudrate': baudrate,
                'printerProfile': '_default',
                'save': True
            }
            
            response = requests.post(
                f"{self.base_url}/api/connection",
                headers=self.headers,
                json=data,
                timeout=self.timeout
            )
            
            if response.status_code == 204:
                logger.info(f"Successfully connected to printer at {port} with baudrate {baudrate}")
                return True
            else:
                logger.error(f"Failed to connect to {port}. Status code: {response.status_code}")
                # USB0로 재시도
                if port == '/dev/ttyACM0' and '/dev/ttyUSB0' not in data['port']:
                    logger.info("Retrying with /dev/ttyUSB0...")
                    return self.connect_printer('/dev/ttyUSB0', baudrate)
                return False
            
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
                headers=self.headers,
                timeout=self.timeout
            )
            if response.status_code == 200:
                connection_info = response.json()
                current_state = connection_info.get('current', {}).get('state')
                current_port = connection_info.get('current', {}).get('port')
                logger.info(f"Printer connection state: {current_state}, port: {current_port}")
                return connection_info
            logger.error(f"Failed to check connection. Status code: {response.status_code}")
            return None
        except requests.exceptions.Timeout:
            logger.error("Connection request timed out")
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

    def move_axis(self, axis, distance):
        """프린터 축 이동"""
        try:
            logger.debug(f"Moving {axis} axis by {distance}mm")
            # OctoPrint API는 상대 이동에 jog 명령을 사용
            response = requests.post(
                f"{self.base_url}/api/printer/printhead",
                headers=self.headers,
                json={
                    "command": "jog",
                    axis.lower(): float(distance)
                },
                timeout=self.timeout
            )
            
            if response.status_code == 204:
                logger.debug(f"Successfully moved {axis} axis")
                return True
            else:
                logger.error(f"Failed to move axis: {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error moving axis: {e}")
            return False

    def home_axis(self, axes=None):
        """축 홈으로 이동"""
        try:
            if axes is None:
                axes = ["x", "y", "z"]
                
            logger.debug(f"Homing axes: {axes}")
            response = requests.post(
                f"{self.base_url}/api/printer/printhead",
                headers=self.headers,
                json={
                    "command": "home",
                    "axes": [axis.lower() for axis in axes]
                },
                timeout=self.timeout
            )
            
            if response.status_code == 204:
                logger.debug("Successfully homed axes")
                return True
            else:
                logger.error(f"Failed to home axes: {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error homing axes: {e}")
            return False

    def get_position(self):
        """프린터의 현재 위치 정보를 가져옴"""
        try:
            response = requests.get(
                f"{self.base_url}/api/printer",
                headers=self.headers
            )
            
            if response.status_code != 200:
                logger.error(f"Failed to get position: {response.text}")
                return None
                
            data = response.json()
            
            # 디버깅을 위해 전체 응답 로깅
            logger.debug(f"Printer API response: {json.dumps(data, indent=2)}")
            
            if 'tool0' in data:
                position = {}
                axes = ['x', 'y', 'z']
                for axis in axes:
                    try:
                        position[axis] = float(data.get(axis, 0))
                    except (TypeError, ValueError):
                        position[axis] = 0.0
                        
                logger.debug(f"Parsed position: {position}")
                return position
                
            return None
            
        except Exception as e:
            logger.error(f"Error getting position: {e}")
            return None

    def _post(self, endpoint, json=None):
        """내부 POST 요청 메소드"""
        try:
            response = requests.post(
                f"{self.base_url}{endpoint}",
                headers=self.headers,
                json=json,
                timeout=self.timeout
            )
            return response
        except Exception as e:
            logger.error(f"Error in POST request to {endpoint}: {e}")
            raise

    def set_fan_speed(self, speed):
        """팬 속도 설정 (0-255)"""
        try:
            logger.debug(f"Setting fan speed to PWM value: {speed}")
            # M106은 팬 켜기(속도 지정), M107은 팬 끄기
            gcode = "M107" if speed == 0 else f"M106 S{speed}"
            response = requests.post(
                f"{self.base_url}/api/printer/command",
                headers=self.headers,
                json={"commands": [gcode]},
                timeout=self.timeout
            )
            logger.debug(f"Fan speed command response: {response.text}")
            return response.ok
        except Exception as e:
            logger.error(f"Error setting fan speed: {e}")
            return False