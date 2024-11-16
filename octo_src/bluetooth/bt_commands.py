from enum import Enum

class BTCommands(Enum):
    GET_STATUS = "GET_STATUS"
    GET_TEMP_HISTORY = "GET_TEMP_HISTORY"
    START_PRINT = "START_PRINT"
    PAUSE = "PAUSE"
    RESUME = "RESUME"
    CANCEL = "CANCEL"
    UPLOAD_GCODE = "UPLOAD_GCODE"
    SET_TEMP = "SET_TEMP"

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