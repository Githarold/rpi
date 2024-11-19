import threading
import time
import logging
from collections import deque
from datetime import datetime

logger = logging.getLogger('mie_printer.temperature')

class TemperatureData:
    def __init__(self, timestamp, tool0_actual, tool0_target, bed_actual, bed_target):
        self.timestamp = timestamp
        self.tool0_actual = tool0_actual
        self.tool0_target = tool0_target
        self.bed_actual = bed_actual
        self.bed_target = bed_target

class TemperatureMonitor:
    def __init__(self, octoprint_client, update_interval=2.0, history_size=1800):  # 1800초 = 30분 (2초 간격)
        self.client = octoprint_client
        self.update_interval = update_interval
        self.is_running = False
        self.monitor_thread = None
        self.last_temp_data = None
        self._connection_error_count = 0
        self.MAX_CONNECTION_ERRORS = 3
        
        # 온도 이력 저장을 위한 deque (최대 1시간)
        self.temp_history = deque(maxlen=history_size)
        
    def start(self):
        """온도 모니터링 시작"""
        if self.is_running:
            return
            
        self.is_running = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop)
        self.monitor_thread.daemon = True
        self.monitor_thread.start()
        logger.info("Temperature monitoring started")
        
    def stop(self):
        """온도 모니터링 중지"""
        self.is_running = False
        if self.monitor_thread:
            self.monitor_thread.join()
        logger.info("Temperature monitoring stopped")
        
    def get_current_temps(self):
        """현재 온도 데이터 반환"""
        return self.last_temp_data

    def get_temperature_history(self, minutes=60):
        """지정된 시간(분) 동안의 온도 이력 반환"""
        if not self.temp_history:
            return []
            
        current_time = datetime.now()
        history_limit = minutes * 60  # 초 단위로 변환
        
        # 지정된 시간 내의 데이터만 필터링
        filtered_history = [
            data for data in self.temp_history
            if (current_time - data.timestamp).total_seconds() <= history_limit
        ]
        
        return filtered_history
        
    def _monitor_loop(self):
        """온도 모니터링 루프"""
        while self.is_running:
            try:
                printer_data = self.client.get_printer_status()
                
                if printer_data is None:
                    # 온도 데이터가 없는 경우 기본값 사용
                    self.last_temp_data = {
                        "tool0": {"actual": 0, "target": 0},
                        "bed": {"actual": 0, "target": 0}
                    }
                    logger.warning("Temperature data not available, using default values")
                else:
                    if 'temperature' in printer_data:
                        self.last_temp_data = printer_data['temperature']
                        
                # 온도 이력 저장 (오류가 있어도 계속 실행)
                temp_data = TemperatureData(
                    timestamp=datetime.now(),
                    tool0_actual=self.last_temp_data['tool0']['actual'],
                    tool0_target=self.last_temp_data['tool0']['target'],
                    bed_actual=self.last_temp_data['bed']['actual'],
                    bed_target=self.last_temp_data['bed']['target']
                )
                self.temp_history.append(temp_data)
                
            except Exception as e:
                logger.warning(f"Error in temperature monitoring: {e}")
                
            time.sleep(self.update_interval) 