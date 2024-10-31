from enum import Enum

class BTCommands(Enum):
    START_PRINT = "START_PRINT"
    PAUSE = "PAUSE"
    RESUME = "RESUME"
    STOP = "STOP"
    GET_STATUS = "GET_STATUS"
    UPLOAD_GCODE = "UPLOAD_GCODE"

class BTResponse:
    @staticmethod
    def success(data=None, message=None):
        response = {"status": "ok"}
        if data is not None:
            response["data"] = data
        if message is not None:
            response["message"] = message
        return response

    @staticmethod
    def error(message):
        return {
            "status": "error",
            "message": message
        }