import serial
import logging
from threading import Lock

logger = logging.getLogger(__name__)

class SerialManager:
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.lock = Lock()
        self.simulation_mode = False

    def close(self):
        """시리얼 연결 종료"""
        if self.serial_conn:
            self.serial_conn.close()
            self.serial_conn = None
        logger.info("Serial connection closed")

    def connect(self):
        try:
            self.serial_conn = serial.Serial(
                self.port,
                self.baudrate,
                timeout=1
            )
            logger.info(f"Serial connection established on {self.port}")
            self.simulation_mode = False
            return True
        except serial.SerialException as e:
            logger.warning(f"Failed to connect to Arduino: {e}. Running in simulation mode.")
            self.simulation_mode = True
            return True  # 연결 실패해도 True 반환

    def send_command(self, command):
        with self.lock:
            try:
                if self.simulation_mode:
                    logger.debug(f"Simulation mode - Command sent: {command}")
                    return "ok"  # 시뮬레이션 모드에서는 항상 "ok" 반환
                    
                if not self.serial_conn:
                    raise Exception("Serial connection not established")
                
                self.serial_conn.write(f"{command}\n".encode())
                response = self.serial_conn.readline().decode().strip()
                return response
            except Exception as e:
                if self.simulation_mode:
                    return "ok"
                logger.error(f"Error sending command: {e}")
                raise