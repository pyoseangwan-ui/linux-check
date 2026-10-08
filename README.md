# Linux 서버 계정관리 취약점 점검 스크립트

CentOS / RHEL 계열 Linux 서버의 계정관리 항목(01~08)을 자동으로 점검하고, 결과를 텍스트 파일로 저장하는 Bash 스크립트입니다.

## 점검 항목

| No | 항목 | 양호 기준 |
|----|------|-----------|
| 01 | Default 계정 삭제 | lp, uucp, nuucp 계정 없음 |
| 02 | 일반 계정 root 권한 관리 | UID 0 계정이 root 하나뿐 |
| 03 | /etc/passwd 파일 권한 설정 | 소유자 root, 644 이하 |
| 04 | /etc/group 파일 권한 설정 | 소유자 root, 644 이하 |
| 05 | 패스워드 사용 규칙 적용 | 최소 길이 8자 이상, 최대 사용기간 70일 이하, 최소 사용기간 1일 이상 |
| 06 | 로그인 불필요 계정 Shell 제한 | 시스템 계정 Shell이 /sbin/nologin 또는 /bin/false |
| 07 | su 명령 사용 제한 | /etc/pam.d/su 에 pam_wheel.so 활성화 또는 su 파일 wheel 그룹/4750 |
| 08 | /etc/shadow 파일 권한 설정 | 소유자 root, 400 이하 |

## 실행 방법

root 계정으로 아래 명령 한 줄을 실행합니다. `학번-이름` 부분은 본인 정보로 바꿉니다.

```bash
curl -fsSL -o 학번-이름.sh https://raw.githubusercontent.com/pyoseangwan-ui/linux-check/main/check.sh && bash 학번-이름.sh
```

- 결과 파일은 스크립트와 같은 이름의 `.txt`로 같은 폴더에 생성됩니다. (예: `학번-이름.sh` → `학번-이름.txt`)
- 터미널에서는 양호/취약이 색상으로 표시되고, 결과 파일에는 색상 코드가 들어가지 않습니다.

## 결과 파일 구성

- 점검 환경 정보 (일시, 호스트명, OS, 커널, 점검 계정)
- 항목별 점검 내용, 판단 기준, 점검 현황, 결과
- 취약 항목의 조치 방법
- 전체 결과 요약 및 보안 준수율

## 주의

인터넷에서 내려받은 스크립트는 실행 전에 내용을 확인하는 것이 안전합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/pyoseangwan-ui/linux-check/main/check.sh | less
```
