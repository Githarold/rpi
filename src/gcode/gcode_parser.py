class GCodeParser:
    def __init__(self):
        pass
        
    def parse_line(self, line):
        line = line.strip()
        if not line or line.startswith(';'):
            return None
            
        # 주석 제거
        if ';' in line:
            line = line.split(';')[0].strip()
            
        # 명령어 파싱
        parts = line.split()
        if not parts:
            return None
            
        command = {
            'command': parts[0],
            'parameters': {}
        }
        
        # 파라미터 파싱
        for part in parts[1:]:
            if len(part) > 1:
                key = part[0]
                try:
                    value = float(part[1:])
                    command['parameters'][key] = value
                except ValueError:
                    pass
                    
        return command