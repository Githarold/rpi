import logging
import threading
import time
from .printer_states import PrinterState, PrinterStatus

logger = logging.getLogger(__name__)

class PrinterManager:
    def __init__(self, serial_manager, gcode_manager):
        self.serial_manager = serial_manager
        self.gcode_manager = gcode_manager
        self.status = PrinterStatus()
        self.is_running = True
        
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

    def _printer_control_loop(self):
        """프린터 제어 루프"""
        while self.is_running:
            try:
                if self.status.state == PrinterState.PRINTING:
                    # 다음 G-code 명령 가져오기
                    command = self.gcode_manager.get_next_command()
                    if command:
                        response = self.serial_manager.send_command(command)
                        if response != 'ok':
                            logger.warning(f"Unexpected response: {response}")
                    
                    # 진행률 업데이트
                    self.status.progress = self.gcode_manager.get_progress()

                    # 온도 정보 업데이트
                    self._update_temperatures()

                time.sleep(0.1)  # CPU 사용률 조절

            except Exception as e:
                logger.error(f"Error in printer control loop: {e}")
                self.status.state = PrinterState.ERROR
                self.status.error = str(e)
                time.sleep(1)

    def _update_temperatures(self):
        """온도 정보 업데이트"""
        try:
            response = self.serial_manager.send_command("M105")
            # 예: "ok T:200.5 /200.0 B:60.3 /60.0"
            if 'T:' in response and 'B:' in response:
                parts = response.split()
                for part in parts:
                    if part.startswith('T:'):
                        self.status.temperatures['nozzle'] = float(part[2:])
                    elif part.startswith('B:'):
                        self.status.temperatures['bed'] = float(part[2:])
        except Exception as e:
            logger.error(f"Error updating temperatures: {e}")