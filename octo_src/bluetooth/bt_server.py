class BluetoothServer:
    def __init__(self, octoprint_client, gcode_manager, service_name="SCARA 3D Printer"):
        self.octoprint_client = octoprint_client
        self.gcode_manager = gcode_manager
        self.server_sock = None
        self.is_running = True
        self.uuid = "00001101-0000-1000-8000-00805F9B34FB"
        self.service_name = service_name

    def handle_command(self, command_str):
        """수신된 명령 처리"""
        try:
            command = json.loads(command_str)
            cmd_type = command.get('type')
            
            if cmd_type == BTCommands.UPLOAD_GCODE.value:
                return self._handle_gcode_upload(command)
            elif cmd_type == BTCommands.START_PRINT.value:
                filename = command.get('filename')
                return json.dumps(
                    BTResponse.success() if self.octoprint_client.start_print(filename)
                    else BTResponse.error("Failed to start print")
                )
            elif cmd_type == BTCommands.GET_STATUS.value:
                status = self.octoprint_client.get_printer_status()
                return json.dumps(BTResponse.success(data=status))
            elif cmd_type == BTCommands.SET_TEMP.value:
                heater = command.get('heater')  # 'tool0' or 'bed'
                target = command.get('target')
                success = self.octoprint_client.set_temperature(heater, target)
                return json.dumps(
                    BTResponse.success() if success
                    else BTResponse.error("Failed to set temperature")
                )
            else:
                return json.dumps(BTResponse.error(f"Unknown command: {cmd_type}"))

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