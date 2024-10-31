from enum import Enum

class MarlinCommands:
    # 온도 관련
    GET_TEMPS = "M105"  # 온도 확인
    SET_HOTEND_TEMP = "M104"  # 핫엔드 온도 설정
    SET_BED_TEMP = "M140"  # 베드 온도 설정
    WAIT_HOTEND_TEMP = "M109"  # 핫엔드 온도 대기
    WAIT_BED_TEMP = "M190"  # 베드 온도 대기
    
    # 모션 관련
    HOME_ALL = "G28"  # 전체 홈
    SET_ABSOLUTE = "G90"  # 절대 좌표계
    SET_RELATIVE = "G91"  # 상대 좌표계
    
    # 프린트 제어
    PAUSE_PRINT = "M25"  # 일시정지
    RESUME_PRINT = "M24"  # 재개
    STOP_PRINT = "M0"   # 정지
    
    # 기타
    RESET_LINE_NUMBERS = "M110 N0"  # 라인 넘버 리셋
    
    @staticmethod
    def set_hotend_temp(temp):
        return f"M104 S{temp}"
        
    @staticmethod
    def set_bed_temp(temp):
        return f"M140 S{temp}"

class MarlinResponses:
    OK = "ok"
    ERROR = "error"
    BUSY = "busy"