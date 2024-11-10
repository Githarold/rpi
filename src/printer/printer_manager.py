import logging
import threading
import time
from .printer_states import PrinterState, PrinterStatus
from ..bluetooth.bt_commands import BTResponse

logger = logging.getLogger(__name__)

class PrinterManager:
    def __init__(self, serial_manager, gcode_manager):
        self.serial_manager = serial_manager
        self.gcode_manager = gcode_manager
        self.status = PrinterStatus()
        self.is_running = True
        
        # 모니터링 스레드 시작
        self.monitor_thread = threading.Thread(target=self._temperature_monitor_loop)
        self.monitor_thread.daemon = True
        self.monitor_thread.start()
        
        # 시뮬레이션 모드 확인
        self.simulation_mode = serial_manager.simulation_mode
        if self.simulation_mode:
            logger.info("Running in simulation mode - No printer connected")

    def upload_gcode(self, filename, content):
        """G-code 파일 업로드"""
        try:
            if self.status.state != PrinterState.IDLE:
                return BTResponse.error("Printer is busy")

            if self.gcode_manager.save_gcode(filename, content):
                return BTResponse.success(message="File uploaded successfully")
            else:
                return BTResponse.error("Failed to save G-code file")

        except Exception as e:
            logger.error(f"Error uploading G-code: {e}")
            return BTResponse.error(str(e))

    def start_print(self, filename):
        """프린트 작업 시작"""
        try:
            if self.status.state != PrinterState.IDLE:
                return BTResponse.error("Printer is busy")
            
            if self.simulation_mode:
                return BTResponse.error("Cannot start print in simulation mode")

            if not self.gcode_manager.load_gcode(filename):
                return BTResponse.error("Failed to load G-code file")

            self.status.state = PrinterState.PRINTING
            self.status.current_file = filename
            self.status.progress = 0

            # 시작 명령 전송
            self.serial_manager.send_command("M110 N0")  # 라인 넘버 리셋
            self.serial_manager.send_command("M109 S200")  # 노즐 예열 (200도)
            self.serial_manager.send_command("M190 S60")   # 베드 예열 (60도)
                
            return BTResponse.success(message="Print started")

        except Exception as e:
            logger.error(f"Error starting print: {e}")
            self.status.state = PrinterState.ERROR
            self.status.error = str(e)
            return BTResponse.error(str(e))

    def pause_print(self):
        """프린트 일시 중지"""
        try:
            if self.status.state != PrinterState.PRINTING:
                return BTResponse.error("No active print job")
            
            if self.simulation_mode:
                return BTResponse.error("Cannot pause print in simulation mode")

            self.serial_manager.send_command("M25")  # Pause SD print
            self.status.state = PrinterState.PAUSED
            return BTResponse.success(message="Print paused")

        except Exception as e:
            logger.error(f"Error pausing print: {e}")
            return BTResponse.error(str(e))

    def resume_print(self):
        """프린트 재개"""
        try:
            if self.status.state != PrinterState.PAUSED:
                return BTResponse.error("Print is not paused")
            
            if self.simulation_mode:
                return BTResponse.error("Cannot resume print in simulation mode")

            self.serial_manager.send_command("M24")  # Resume SD print
            self.status.state = PrinterState.PRINTING
            return BTResponse.success(message="Print resumed")

        except Exception as e:
            logger.error(f"Error resuming print: {e}")
            return BTResponse.error(str(e))

    def stop_print(self):
        """프린트 중지"""
        try:
            if self.status.state not in [PrinterState.PRINTING, PrinterState.PAUSED]:
                return BTResponse.error("No active print job")
            
            if self.simulation_mode:
                return BTResponse.error("Cannot stop print in simulation mode")

            self.serial_manager.send_command("M0")  # Stop print
            self.status.state = PrinterState.IDLE
            self.status.progress = 0
            self.status.current_file = None
            return BTResponse.success(message="Print stopped")

        except Exception as e:
            logger.error(f"Error stopping print: {e}")
            return BTResponse.error(str(e))

    def get_status(self):
        """현재 프린터 상태 반환"""
        return self.status.to_dict()

    def _temperature_monitor_loop(self):
        """온도 모니터링 루프"""
        while self.is_running:
            try:
                if not self.simulation_mode:
                    response = self.serial_manager.send_command("M105")
                    if 'T:' in response and 'B:' in response:
                        self._parse_temperature(response)
                else:
                    # 시뮬레이션 모드에서는 가상의 온도 데이터 생성
                    self.status.temperatures['nozzle'] = 200.0
                    self.status.temperatures['bed'] = 60.0
                
                time.sleep(5)  # 5초마다 업데이트
                
            except Exception as e:
                logger.error(f"Temperature monitoring error: {e}")
                time.sleep(5)  # 에러 발생시 5초 대기

    def _parse_temperature(self, response):
        """온도 응답 파싱"""
        try:
            parts = response.split()
            for part in parts:
                if part.startswith('T:'):
                    self.status.temperatures['nozzle'] = float(part[2:])
                elif part.startswith('B:'):
                    self.status.temperatures['bed'] = float(part[2:])
        except Exception as e:
            logger.error(f"Error parsing temperature response: {e}")

__all__ = ['PrinterManager']