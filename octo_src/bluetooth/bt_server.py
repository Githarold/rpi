import bluetooth
import json
import logging
import threading
import os
from .bt_commands import BTCommands, BTResponse

# 로거 설정
logger = logging.getLogger('mie_printer.bluetooth')

class BluetoothServer:
    def __init__(self, octoprint_client, gcode_manager, service_name="SCARA 3D Printer"):
        self.octoprint_client = octoprint_client
        self.gcode_manager = gcode_manager
        self.server_sock = None
        self.is_running = True
        self.uuid = "00001101-0000-1000-8000-00805F9B34FB"
        self.service_name = service_name

    def setup_server(self):
        """블루투스 서버 설정"""
        try:
            if not os.path.exists('/var/run/sdp'):
                logger.warning("SDP directory does not exist")
                os.system('sudo mkdir -p /var/run/sdp')
        
            os.system('sudo chmod -R 777 /var/run/sdp')
            logger.info("SDP permissions set")
                
            self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            port = bluetooth.PORT_ANY
            self.server_sock.bind(("", port))
            self.server_sock.listen(1)

            bluetooth.advertise_service(
                self.server_sock, 
                self.service_name,
                service_id=self.uuid,
                service_classes=[self.uuid, bluetooth.SERIAL_PORT_CLASS],
                profiles=[bluetooth.SERIAL_PORT_PROFILE]
            )
            logger.info(f"Bluetooth server started on RFCOMM channel {self.server_sock.getsockname()[1]}")
            return True
        except Exception as e:
            logger.error(f"Failed to setup bluetooth server: {e}")
            return False

    def handle_command(self, command_str):
        """수신된 명령 처리"""
        try:
            command = json.loads(command_str)
            cmd_type = command.get('type')
            
            if cmd_type == BTCommands.PAUSE.value:
                return json.dumps(
                    BTResponse.success() if self.octoprint_client.pause_print()
                    else BTResponse.error("Failed to pause print")
                )
                
            elif cmd_type == BTCommands.RESUME.value:
                return json.dumps(
                    BTResponse.success() if self.octoprint_client.resume_print()
                    else BTResponse.error("Failed to resume print")
                )
                
            elif cmd_type == BTCommands.CANCEL.value:
                return json.dumps(
                    BTResponse.success() if self.octoprint_client.cancel_print()
                    else BTResponse.error("Failed to cancel print")
                )
                
            elif cmd_type == BTCommands.UPLOAD_GCODE.value:
                # 파일이 이미 존재하는지 확인
                filename = command.get('filename')
                action = command.get('action')
                
                # 파일이 이미 존재하면 모든 업로드 관련 명령을 성공으로 처리
                if filename and self.gcode_manager.is_file_ready(filename):
                    logger.info(f"File {filename} already exists, skipping upload")
                    if action == 'start':
                        return json.dumps(BTResponse.success(message="File already exists"))
                    elif action == 'chunk':
                        return json.dumps(BTResponse.success(message="Chunk skipped"))
                    elif action == 'finish':
                        return json.dumps(BTResponse.success(message="Upload skipped"))
                    
                # 파일이 없는 경우에만 업로드 처리
                return self._handle_gcode_upload(command)
                
            elif cmd_type == BTCommands.START_PRINT.value:
                filename = command.get('filename')
                if not filename:
                    return json.dumps(BTResponse.error("Missing filename"))
                    
                # 파일 존재 확인
                if not self.gcode_manager.is_file_ready(filename):
                    return json.dumps(BTResponse.error("File not found or incomplete"))
                    
                # 출력 시작
                return json.dumps(
                    BTResponse.success() if self.octoprint_client.start_print(filename)
                    else BTResponse.error("Failed to start print")
                )
                
            elif cmd_type == BTCommands.GET_STATUS.value:
                status = self.octoprint_client.get_printer_status()
                if status:
                    response_data = {
                        'temperature': status['temperature'],
                        'fan_speed': status['fan_speed'],
                        'progress': status['progress'],
                        'currentFile': status['currentFile'],
                        'timeLeft': status['timeLeft'],
                        'currentLayer': status['currentLayer'],
                        'totalLayers': status['totalLayers']
                    }
                    return json.dumps(BTResponse.success(data=response_data))
                else:
                    return json.dumps(BTResponse.error("Failed to get printer status"))
                
            elif cmd_type == BTCommands.SET_TEMP.value:
                heater = command.get('heater')  # 'tool0' or 'bed'
                target = command.get('target')
                success = self.octoprint_client.set_temperature(heater, target)
                return json.dumps(
                    BTResponse.success() if success
                    else BTResponse.error("Failed to set temperature")
                )
                
            elif cmd_type == BTCommands.GET_TEMP_HISTORY.value:
                minutes = command.get('minutes', 60)  # 기본값 60분
                history = self.temp_monitor.get_temperature_history(minutes)
                
                # 온도 이력 데이터를 JSON 직렬화 가능한 형식으로 변환
                history_data = [
                    {
                        'timestamp': data.timestamp.isoformat(),
                        'tool0': {
                            'actual': data.tool0_actual,
                            'target': data.tool0_target
                        },
                        'bed': {
                            'actual': data.bed_actual,
                            'target': data.bed_target
                        }
                    }
                    for data in history
                ]
                
                return json.dumps(BTResponse.success(data=history_data))
                
            else:
                return json.dumps(BTResponse.error(f"Unknown command: {cmd_type}"))
                
        except Exception as e:
            logger.error(f"Error handling command: {e}")
            return json.dumps(BTResponse.error(str(e)))

    def _handle_gcode_upload(self, command):
        """G-code 파일 업로드 처리"""
        try:
            action = command.get('action')
            
            if action == 'start':
                filename = command.get('filename')
                total_size = command.get('total_size')
                if not filename or not total_size:
                    return json.dumps(BTResponse.error("Missing filename or total_size"))
                success = self.gcode_manager.init_upload(filename, total_size)
                if not success:
                    return json.dumps(BTResponse.error("Failed to initialize upload"))
                return json.dumps(BTResponse.success(message="Upload initialized"))
                
            elif action == 'chunk':
                chunk_data = command.get('data')
                chunk_index = command.get('chunk_index', 0)
                total_chunks = command.get('total_chunks', 1)
                is_last = command.get('is_last', True)
                
                if not chunk_data:
                    return json.dumps(BTResponse.error("Empty chunk data"))
                    
                success = self.gcode_manager.append_chunk(
                    chunk_data, 
                    chunk_index=chunk_index,
                    total_chunks=total_chunks,
                    is_last=is_last
                )
                if not success:
                    return json.dumps(BTResponse.error("Failed to append chunk"))
                return json.dumps(BTResponse.success(message="Chunk received"))
                
            elif action == 'finish':
                filename = command.get('filename')
                if not filename:
                    return json.dumps(BTResponse.error("Missing filename"))
                success = self.gcode_manager.finalize_upload(filename)
                if not success:
                    return json.dumps(BTResponse.error("Failed to finalize upload"))
                return json.dumps(BTResponse.success(message="Upload completed"))
                
            else:
                return json.dumps(BTResponse.error(f"Unknown upload action: {action}"))
                
        except Exception as e:
            logger.error(f"Error handling gcode upload: {e}")
            return json.dumps(BTResponse.error(str(e)))

    def handle_client(self, client_sock, client_info):
        """클라이언트 연결 처리"""
        data_buffer = ""
        try:
            while True:
                data = client_sock.recv(1024).decode('utf-8')
                if not data:
                    break
                data_buffer += data

                while '\n' in data_buffer:
                    message, data_buffer = data_buffer.split('\n', 1)
                    response = self.handle_command(message)
                    client_sock.send((response + '\n').encode('utf-8'))
        except Exception as e:
            logger.error(f"Error handling client {client_info}: {e}")
        finally:
            client_sock.close()
            logger.info(f"Connection with {client_info} closed.")

    def start(self):
        """서버 시작"""
        if not self.setup_server():
            return

        try:
            while self.is_running:
                try:
                    client_sock, client_info = self.server_sock.accept()
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_sock, client_info)
                    )
                    client_thread.daemon = True
                    client_thread.start()
                except Exception as e:
                    logger.error(f"Error accepting connection: {e}")

        except KeyboardInterrupt:
            logger.info("Server stopping...")
        finally:
            self.cleanup()

    def cleanup(self):
        """리소스 정리"""
        self.is_running = False
        if self.server_sock:
            self.server_sock.close()