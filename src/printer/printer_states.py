from enum import Enum

class PrinterState(Enum):
    IDLE = "idle"
    PRINTING = "printing"
    PAUSED = "paused"
    ERROR = "error"

class PrinterStatus:
    def __init__(self):
        self.state = PrinterState.IDLE
        self.current_file = None
        self.progress = 0
        self.error = None
        self.temperatures = {
            "nozzle": 0,
            "bed": 0
        }

    def to_dict(self):
        return {
            "status": self.state.value,
            "current_file": self.current_file,
            "progress": self.progress,
            "error": self.error,
            "temperatures": self.temperatures
        }