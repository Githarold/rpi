import os
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class GCodeManager:
    def __init__(self, gcode_folder):
        self.gcode_folder = Path(gcode_folder)
        self.gcode_folder.mkdir(exist_ok=True)
        self.current_file = None
        self.current_lines = None
        self.current_line_number = 0

    def save_gcode(self, filename, content):
        try:
            file_path = self.gcode_folder / filename
            with open(file_path, 'w') as f:
                f.write(content)
            logger.info(f"Successfully saved G-code file: {filename}")
            return True
        except Exception as e:
            logger.error(f"Error saving G-code file: {e}")
            return False

    def load_gcode(self, filename):
        try:
            file_path = self.gcode_folder / filename
            with open(file_path, 'r') as f:
                self.current_lines = [line.strip() for line in f.readlines()]
                self.current_file = filename
                self.current_line_number = 0
            return True
        except Exception as e:
            logger.error(f"Error loading G-code file: {e}")
            return False

    def get_next_command(self):
        if not self.current_lines:
            return None

        while self.current_line_number < len(self.current_lines):
            line = self.current_lines[self.current_line_number].strip()
            self.current_line_number += 1
            
            if line and not line.startswith(';'):
                return line

        return None

    def get_progress(self):
        if not self.current_lines:
            return 0
        return (self.current_line_number / len(self.current_lines)) * 100