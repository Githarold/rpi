import bluetooth
import json
import logging
import threading
import os
from .bt_commands import BTCommands, BTResponse

# 로거 설정을 DEBUG 레벨로 변경
logger = logging.getLogger('mie_printer.bluetooth')
logger.setLevel(logging.DEBUG)

class BluetoothServer:
    def __init__(self, octoprint_client, gcode_manager, temp_monitor, service_name="SCARA 3D Printer"):
        self.octoprint_client = octoprint_client
        self.gcode_manager = gcode_manager
        self.temp_monitor = temp_monitor
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
            logger.debug(f"Processing command: {command_str!r}")
            command = json.loads(command_str)
            cmd_type = command.get('type')
            logger.debug(f"Command type: {cmd_type}")
            
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
                target = command.get('target')
                temp = command.get('temperature')
                if not target or temp is None:
                    return json.dumps(BTResponse.error("Missing target or temperature"))
                
                if target not in ['bed', 'nozzle']:
                    return json.dumps(BTResponse.error("Invalid target. Must be 'bed' or 'nozzle'"))
                
                try:
                    temp = float(temp)
                    if target == 'bed':
                        self.octoprint_client.set_bed_temp(temp)
                    else:
                        self.octoprint_client.set_nozzle_temp(temp)
                    return json.dumps(BTResponse.success())
                except ValueError:
                    return json.dumps(BTResponse.error("Invalid temperature value"))
                except Exception as e:
                    return json.dumps(BTResponse.error(f"Failed to set temperature: {str(e)}"))

            elif cmd_type == BTCommands.SET_FAN_SPEED.value:
                speed = command.get('speed')
                if speed is None:
                    logger.error("Missing fan speed value")
                    return json.dumps(BTResponse.error("Missing fan speed"))
                
                try:
                    # 들어오는 값이 이미 PWM 값(0-255)이므로 변환하지 않음
                    logger.debug(f"Setting fan speed to PWM value: {speed}")
                    result = self.octoprint_client.set_fan_speed(speed)
                    
                    if isinstance(result, dict):
                        # 성공적으로 설정되고 상태가 반환된 경우
                        return json.dumps(BTResponse.success(data=result))
                    elif result:
                        # 성공했지만 상태가 없는 경우
                        return json.dumps(BTResponse.success())
                    else:
                        # 실패한 경우
                        return json.dumps(BTResponse.error("Failed to set fan speed"))
                except Exception as e:
                    logger.error(f"Error setting fan speed: {e}")
                    return json.dumps(BTResponse.error(f"Failed to set fan speed: {str(e)}"))

            elif cmd_type == BTCommands.SET_FLOW_RATE.value:
                rate = command.get('rate')
                if rate is None:
                    return json.dumps(BTResponse.error("Missing flow rate"))
                
                try:
                    rate = float(rate)
                    if not 75 <= rate <= 125:  # 일반적인 안전 범위
                        return json.dumps(BTResponse.error("Flow rate must be between 75 and 125"))
                    
                    self.octoprint_client.set_flow_rate(rate)
                    return json.dumps(BTResponse.success())
                except ValueError:
                    return json.dumps(BTResponse.error("Invalid flow rate value"))
                except Exception as e:
                    return json.dumps(BTResponse.error(f"Failed to set flow rate: {str(e)}"))

            elif cmd_type in [BTCommands.EXTRUDE.value, BTCommands.RETRACT.value]:
                amount = command.get('amount')
                if amount is None:
                    return json.dumps(BTResponse.error("Missing amount"))
                
                try:
                    amount = float(amount)
                    if not 0 < abs(amount) <= 100:  # 안전을 위한 최대값 제한
                        return json.dumps(BTResponse.error("Amount must be between 0 and 100"))
                    
                    # Retract일 경우 음수로 변환
                    if cmd_type == BTCommands.RETRACT.value:
                        amount = -amount
                    
                    self.octoprint_client.extrude(amount)
                    return json.dumps(BTResponse.success())
                except ValueError:
                    return json.dumps(BTResponse.error("Invalid amount value"))
                except Exception as e:
                    return json.dumps(BTResponse.error(f"Failed to extrude/retract: {str(e)}"))

            elif cmd_type == BTCommands.GET_TEMP_HISTORY.value:
                minutes = command.get('minutes', 60)  # 기본값 60분
                history = self.temp_monitor.get_temperature_history(minutes)
                
                # 온도 데이터를 JSON 직렬화 가능한 형식으로 변환
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
                
            elif cmd_type == BTCommands.GET_POSITION.value:
                response = self.octoprint_client.get_position()
                return json.dumps(BTResponse.success(data=response))
                
            elif cmd_type == BTCommands.MOVE_AXIS.value:
                axis = command.get('axis')
                distance = command.get('distance')
                
                if not axis or distance is None:
                    return json.dumps(BTResponse.error("Missing axis or distance"))
                
                try:
                    success = self.octoprint_client.move_axis(axis, float(distance))
                    logger.debug(f"Moving {axis} axis by {distance}mm")
                    return json.dumps(
                        BTResponse.success() if success
                        else BTResponse.error(f"Failed to move {axis} axis")
                    )
                except ValueError:
                    return json.dumps(BTResponse.error("Invalid distance value"))
                except Exception as e:
                    logger.error(f"Error moving axis: {e}")
                    return json.dumps(BTResponse.error(str(e)))
                    
            elif cmd_type == BTCommands.HOME_AXIS.value:
                axes = command.get('axes', ['x', 'y', 'z'])  # 기본값으로 모든 축
                try:
                    success = self.octoprint_client.home_axis(axes)
                    logger.debug(f"Homing axes: {axes}")
                    return json.dumps(
                        BTResponse.success() if success
                        else BTResponse.error("Failed to home axes")
                    )
                except Exception as e:
                    logger.error(f"Error homing axes: {e}")
                    return json.dumps(BTResponse.error(str(e)))

            else:
                return json.dumps(BTResponse.error(f"Unknown command: {cmd_type}"))
                
        except json.JSONDecodeError as e:
            logger.error(f"JSONDecodeError: {e} - Raw command: {command_str}")
            return json.dumps(BTResponse.error(f"Invalid JSON data: {str(e)}"))
        except Exception as e:
            logger.error(f"Error handling command: {e} - Raw command: {command_str}")
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
                try:
                    data = client_sock.recv(1024).decode('utf-8')
                    if not data:
                        logger.debug("No data received, client disconnected")
                        break
                    
                    logger.debug(f"Received raw data: {data!r}")
                    data_buffer += data
                    
                    while '{' in data_buffer and '}' in data_buffer:
                        start = data_buffer.find('{')
                        end = data_buffer.find('}', start) + 1
                        if start != -1 and end != 0:
                            message = data_buffer[start:end]
                            data_buffer = data_buffer[end:]
                            logger.debug(f"Processing message: {message!r}")
                            
                            try:
                                # JSON 유효성 검사
                                json.loads(message)
                                response = self.handle_command(message)
                                logger.debug(f"Sending response: {response!r}")
                                client_sock.send((response + '\n').encode('utf-8'))
                            except json.JSONDecodeError as e:
                                logger.error(f"Invalid JSON: {e} in message: {message!r}")
                                
                except Exception as e:
                    logger.error(f"Error receiving data: {e}")
                    break
                    
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