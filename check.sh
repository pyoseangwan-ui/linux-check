#!/bin/bash
#==========================================================================
#  Linux 서버 취약점 점검 스크립트 - 계정 관리 (01 ~ 08)
#--------------------------------------------------------------------------
#  대상 OS : CentOS / RHEL 계열 Linux
#  실행    : curl -fsSL -o 학번-이름.sh <raw URL> && bash 학번-이름.sh   (root 권한 권장)
#  결과    : 스크립트와 같은 이름의 .txt 파일이 같은 폴더에 생성됨
#            (예: 20231234-홍길동.sh  ->  20231234-홍길동.txt)
#--------------------------------------------------------------------------
#  01. Default 계정 삭제              05. 패스워드 사용 규칙 적용
#  02. 일반 계정 root 권한 관리        06. 로그인 불필요 계정 Shell 제한
#  03. /etc/passwd 파일 권한 설정      07. su 명령 사용 제한
#  04. /etc/group 파일 권한 설정       08. /etc/shadow 파일 권한 설정
#==========================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_NAME=$(basename "$0")
RESULT_FILE="$SCRIPT_DIR/${SCRIPT_NAME%.*}.txt"

: > "$RESULT_FILE"

RESULT_NO=()
RESULT_TITLE=()
RESULT_STAT=()

#--------------------------------------------------------------------------
#  공통 함수
#--------------------------------------------------------------------------
p()         { echo "$*" >> "$RESULT_FILE"; }
line_eq()   { p "=========================================================================="; }
line_dash() { p "--------------------------------------------------------------------------"; }
is_num()    { [[ "$1" =~ ^[0-9]+$ ]]; }

# 현재 권한($1)이 기준 권한($2) 이하인지 (기준에 없는 비트가 하나라도 있으면 실패)
perm_ok() { [ $(( 8#$1 & ~8#$2 & 07777 )) -eq 0 ]; }

# $1 번호  $2 항목명  $3 점검 내용  $4 양호 기준  $5 취약 기준
item_start() {
    CUR_NO="$1"; CUR_TITLE="$2"
    p ""
    line_eq
    p " [$1] $2"
    line_eq
    p " ■ 점검 내용 : $3"
    p " ■ 판단 기준 : (양호) $4"
    p "               (취약) $5"
    p ""
    p " ■ 점검 현황"
}

# $1 결과(양호/취약/N/A)  $2.. 조치 방법(취약일 때만 출력)
item_end() {
    local stat="$1"; shift
    p ""
    p " ■ 점검 결과 : [ $stat ]"
    if [ "$stat" = "취약" ] && [ $# -gt 0 ]; then
        p ""
        p " ■ 조치 방법"
        for l in "$@"; do p "   $l"; done
    fi
    RESULT_NO+=("$CUR_NO")
    RESULT_TITLE+=("$CUR_TITLE")
    RESULT_STAT+=("$stat")
}

# 파일 소유자 / 권한 점검 ($1 파일  $2 기준 권한)  -> FP_STAT 에 결과
check_file_perm() {
    local f="$1" max="$2" perm owner
    if [ ! -f "$f" ]; then
        p "   - $f 파일이 존재하지 않음"
        FP_STAT="N/A"
        return
    fi
    perm=$(stat -L -c %a "$f")
    owner=$(stat -L -c %U "$f")
    p "   - $(ls -alL "$f")"
    p "   - 소유자 : $owner  /  권한 : $perm   (기준 : root / $max 이하)"
    if [ "$owner" = "root" ] && perm_ok "$perm" "$max"; then
        FP_STAT="양호"
    else
        FP_STAT="취약"
    fi
}

#--------------------------------------------------------------------------
#  점검 환경 정보
#--------------------------------------------------------------------------
if [ -f /etc/redhat-release ]; then
    OS_INFO=$(cat /etc/redhat-release)
elif [ -f /etc/os-release ]; then
    OS_INFO=$(. /etc/os-release; echo "$PRETTY_NAME")
else
    OS_INFO=$(uname -s)
fi

line_eq
p "            Linux 서버 취약점 점검 결과 보고 (계정 관리 01 ~ 08)"
line_eq
p "  점검 일시   : $(date '+%Y-%m-%d %H:%M:%S')"
p "  호스트명    : $(hostname)"
p "  운영체제    : $OS_INFO"
p "  커널 버전   : $(uname -r)"
p "  점검 계정   : $(whoami) (UID=$EUID)"
p "  점검 스크립트 : $SCRIPT_NAME"
line_eq

if [ "$EUID" -ne 0 ]; then
    p "  ※ root 권한이 아닌 상태로 실행됨 - 일부 결과가 정확하지 않을 수 있음"
fi

#--------------------------------------------------------------------------
#  01. Default 계정 삭제
#--------------------------------------------------------------------------
item_start "01" "Default 계정 삭제" \
    "OS 설치 시 기본 생성되는 불필요한 계정(lp, uucp, nuucp) 존재 여부" \
    "lp, uucp, nuucp 계정이 존재하지 않음" \
    "lp, uucp, nuucp 계정 중 하나 이상 존재함"

if [ -f /etc/passwd ]; then
    FOUND=""
    for id in lp uucp nuucp; do
        ENTRY=$(grep "^${id}:" /etc/passwd)
        if [ -n "$ENTRY" ]; then
            FOUND="$FOUND $id"
            p "   - 발견 : $ENTRY"
        fi
    done
    if [ -z "$FOUND" ]; then
        p "   - 불필요한 기본 계정(lp, uucp, nuucp) 없음"
        item_end "양호"
    else
        item_end "취약" \
            "불필요한 계정 삭제 :${FOUND}" \
            "# userdel <계정명>     (예: userdel lp)"
    fi
else
    p "   - /etc/passwd 파일이 존재하지 않음"
    item_end "N/A"
fi

#--------------------------------------------------------------------------
#  02. 일반 계정 root 권한 관리
#--------------------------------------------------------------------------
item_start "02" "일반 계정 root 권한 관리" \
    "root 이외에 UID가 0인 계정 존재 여부" \
    "UID 0 계정이 root 하나뿐임" \
    "root 이외에 UID 0 계정이 존재함"

if [ -f /etc/passwd ]; then
    UID0=$(awk -F: '$3==0 {print $1}' /etc/passwd)
    OTHERS=$(echo "$UID0" | grep -v '^root$')
    for u in $UID0; do
        p "   - UID 0 계정 : $(grep "^${u}:" /etc/passwd)"
    done
    if [ -z "$OTHERS" ]; then
        item_end "양호"
    else
        item_end "취약" \
            "root 이외 UID 0 계정 : $(echo $OTHERS)" \
            "# usermod -u <사용하지 않는 UID> <계정명>   (예: usermod -u 2001 test)"
    fi
else
    p "   - /etc/passwd 파일이 존재하지 않음"
    item_end "N/A"
fi

#--------------------------------------------------------------------------
#  03. /etc/passwd 파일 권한 설정
#--------------------------------------------------------------------------
item_start "03" "/etc/passwd 파일 권한 설정" \
    "/etc/passwd 파일의 소유자 및 권한" \
    "소유자 root, 권한 644(-rw-r--r--) 이하" \
    "소유자가 root가 아니거나 권한이 644 초과"

check_file_perm /etc/passwd 644
item_end "$FP_STAT" \
    "# chown root /etc/passwd" \
    "# chmod 644 /etc/passwd"

#--------------------------------------------------------------------------
#  04. /etc/group 파일 권한 설정
#--------------------------------------------------------------------------
item_start "04" "/etc/group 파일 권한 설정" \
    "/etc/group 파일의 소유자 및 권한" \
    "소유자 root, 권한 644(-rw-r--r--) 이하" \
    "소유자가 root가 아니거나 권한이 644 초과"

check_file_perm /etc/group 644
item_end "$FP_STAT" \
    "# chown root /etc/group" \
    "# chmod 644 /etc/group"

#--------------------------------------------------------------------------
#  05. 패스워드 사용 규칙 적용
#--------------------------------------------------------------------------
item_start "05" "패스워드 사용 규칙 적용" \
    "/etc/login.defs 의 패스워드 최소 길이, 최대/최소 사용 기간 설정" \
    "최소 길이 8자 이상, 최대 사용기간 70일 이하, 최소 사용기간 1일 이상" \
    "위 기준 중 하나라도 만족하지 않거나 미설정"

LOGIN_DEFS=/etc/login.defs
if [ -f "$LOGIN_DEFS" ]; then
    get_def() { awk -v k="$1" '$1==k {v=$2} END {print v}' "$LOGIN_DEFS"; }

    PW_LEN=$(get_def PASS_MIN_LEN)
    PW_MAX=$(get_def PASS_MAX_DAYS)
    PW_MIN=$(get_def PASS_MIN_DAYS)

    # CentOS 7 이후 PASS_MIN_LEN 미지원 -> pwquality.conf 의 minlen 보조 확인
    LEN_SRC="login.defs"
    if ! is_num "$PW_LEN" && [ -f /etc/security/pwquality.conf ]; then
        Q=$(awk -F= '/^[[:space:]]*minlen[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); v=$2} END {print v}' /etc/security/pwquality.conf)
        if is_num "$Q"; then
            PW_LEN="$Q"
            LEN_SRC="pwquality.conf minlen"
        fi
    fi

    PW_BAD=0
    sub_check() {   # $1 항목  $2 값  $3 비교연산  $4 기준값  $5 기준 설명
        if ! is_num "$2"; then
            p "   - $(printf '%-14s' "$1") : 미설정            (기준 : $5)  -> 취약"
            PW_BAD=1
        elif [ "$2" "$3" "$4" ]; then
            p "   - $(printf '%-14s' "$1") : $(printf '%-17s' "$2") (기준 : $5)  -> 양호"
        else
            p "   - $(printf '%-14s' "$1") : $(printf '%-17s' "$2") (기준 : $5)  -> 취약"
            PW_BAD=1
        fi
    }
    sub_check "PASS_MIN_LEN"  "$PW_LEN" -ge 8  "8자 이상"
    [ "$LEN_SRC" != "login.defs" ] && p "       (login.defs 미설정으로 $LEN_SRC 값 적용)"
    sub_check "PASS_MAX_DAYS" "$PW_MAX" -le 70 "70일 이하"
    sub_check "PASS_MIN_DAYS" "$PW_MIN" -ge 1  "1일 이상"

    if [ "$PW_BAD" -eq 0 ]; then
        item_end "양호"
    else
        item_end "취약" \
            "# vi /etc/login.defs 에서 아래와 같이 수정" \
            "  PASS_MAX_DAYS   70" \
            "  PASS_MIN_DAYS   1" \
            "  PASS_MIN_LEN    8" \
            "(CentOS 7 이상은 /etc/security/pwquality.conf 의 'minlen = 8' 도 함께 설정)"
    fi
else
    p "   - $LOGIN_DEFS 파일이 존재하지 않음"
    item_end "N/A"
fi

#--------------------------------------------------------------------------
#  06. 로그인 불필요 계정 Shell 제한
#--------------------------------------------------------------------------
item_start "06" "로그인 불필요 계정 Shell 제한" \
    "로그인이 필요 없는 시스템 계정에 로그인 가능한 Shell 부여 여부" \
    "시스템 계정의 Shell이 /sbin/nologin 또는 /bin/false" \
    "시스템 계정에 로그인 가능한 Shell(/bin/bash 등)이 부여됨"

if [ -f /etc/passwd ]; then
    SHELL_BAD=""
    CHECKED=0
    for a in daemon bin sys adm listen nobody nobody4 noaccess diag operator games gopher; do
        grep -q "^${a}:" /etc/passwd || continue
        CHECKED=$((CHECKED + 1))
        SH=$(awk -F: -v u="$a" '$1==u {print $7}' /etc/passwd)
        case "$SH" in
            /sbin/nologin|/usr/sbin/nologin|/bin/false|/usr/bin/false) ST="양호" ;;
            *) ST="취약"; SHELL_BAD="$SHELL_BAD $a" ;;
        esac
        p "   - $(printf '%-10s : %-20s' "$a" "${SH:-(미지정)}") -> $ST"
    done
    if [ "$CHECKED" -eq 0 ]; then
        p "   - 점검 대상 시스템 계정 없음"
        item_end "양호"
    elif [ -z "$SHELL_BAD" ]; then
        item_end "양호"
    else
        item_end "취약" \
            "로그인 가능 Shell 부여 계정 :${SHELL_BAD}" \
            "# usermod -s /sbin/nologin <계정명>"
    fi
else
    p "   - /etc/passwd 파일이 존재하지 않음"
    item_end "N/A"
fi

#--------------------------------------------------------------------------
#  07. su 명령 사용 제한
#--------------------------------------------------------------------------
item_start "07" "su 명령 사용 제한" \
    "su 명령을 wheel 그룹 사용자만 사용할 수 있도록 제한했는지 여부" \
    "/etc/pam.d/su 에 pam_wheel.so 설정 활성화 또는 su 파일이 wheel 그룹/4750 권한" \
    "su 명령을 모든 사용자가 사용할 수 있음"

PAM_OK=0
BIN_OK=0
PAM_SU=/etc/pam.d/su

if [ -f "$PAM_SU" ]; then
    PAM_LINE=$(grep -E '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_wheel\.so' "$PAM_SU")
    if [ -n "$PAM_LINE" ]; then
        PAM_OK=1
        p "   - $PAM_SU : 설정 활성화"
        p "       $PAM_LINE"
    else
        p "   - $PAM_SU : pam_wheel.so 제한 설정 없음 (또는 주석 처리)"
        grep -E 'pam_wheel\.so' "$PAM_SU" | while IFS= read -r l; do p "       $l"; done
    fi
else
    p "   - $PAM_SU 파일이 존재하지 않음"
fi

SU_BIN=/bin/su
[ -e "$SU_BIN" ] || SU_BIN=/usr/bin/su
if [ -e "$SU_BIN" ]; then
    SU_PERM=$(stat -L -c %a "$SU_BIN")
    SU_GRP=$(stat -L -c %G "$SU_BIN")
    p "   - $(ls -alL "$SU_BIN")"
    if [ "$SU_GRP" = "wheel" ] && [ "${SU_PERM: -1}" = "0" ]; then
        BIN_OK=1
    fi
fi

WHEEL=$(grep '^wheel:' /etc/group 2>/dev/null)
if [ -n "$WHEEL" ]; then
    MEMBERS=$(echo "$WHEEL" | cut -d: -f4)
    p "   - wheel 그룹 구성원 : ${MEMBERS:-(없음)}"
else
    p "   - wheel 그룹이 존재하지 않음"
fi

if [ "$PAM_OK" -eq 1 ] || [ "$BIN_OK" -eq 1 ]; then
    item_end "양호"
else
    item_end "취약" \
        "# vi /etc/pam.d/su 에서 아래 줄의 주석(#) 제거" \
        "  auth    required    pam_wheel.so use_uid" \
        "# usermod -aG wheel <su 사용 허용 계정>"
fi

#--------------------------------------------------------------------------
#  08. /etc/shadow 파일 권한 설정
#--------------------------------------------------------------------------
item_start "08" "/etc/shadow 파일 권한 설정" \
    "/etc/shadow 파일의 소유자 및 권한" \
    "소유자 root, 권한 400(-r--------) 이하" \
    "소유자가 root가 아니거나 권한이 400 초과"

check_file_perm /etc/shadow 400
item_end "$FP_STAT" \
    "# chown root /etc/shadow" \
    "# chmod 400 /etc/shadow"

#--------------------------------------------------------------------------
#  점검 결과 요약
#--------------------------------------------------------------------------
GOOD=0; BAD=0; NA=0
p ""
line_eq
p " [ 점검 결과 요약 ]"
line_eq
for i in "${!RESULT_NO[@]}"; do
    case "${RESULT_STAT[$i]}" in
        양호) GOOD=$((GOOD + 1)) ;;
        취약) BAD=$((BAD + 1)) ;;
        *)    NA=$((NA + 1)) ;;
    esac
    S="${RESULT_STAT[$i]}"
    [ "$S" = "N/A" ] && S="N/A "
    p "   [ $S ]  ${RESULT_NO[$i]}. ${RESULT_TITLE[$i]}"
done
line_dash
TOTAL=$((GOOD + BAD))
if [ "$TOTAL" -gt 0 ]; then
    SCORE=$((GOOD * 100 / TOTAL))
else
    SCORE=0
fi
p "   양호 : $GOOD   취약 : $BAD   N/A : $NA   ->   보안 준수율 : ${SCORE}%"
line_eq
p "   결과 파일 : $RESULT_FILE"
line_eq

#--------------------------------------------------------------------------
#  화면 출력 (터미널에서만 색상 표시, 결과 파일에는 색상 코드 미포함)
#--------------------------------------------------------------------------
if [ -t 1 ]; then
    G=$'\e[1;32m'; R=$'\e[1;31m'; Y=$'\e[1;33m'; N=$'\e[0m'
    sed -e "s/\[ 양호 \]/${G}[ 양호 ]${N}/g" \
        -e "s/\[ 취약 \]/${R}[ 취약 ]${N}/g" \
        -e "s/\[ N\/A \{1,2\}\]/${Y}&${N}/g" \
        -e "s/-> 양호/-> ${G}양호${N}/g" \
        -e "s/-> 취약/-> ${R}취약${N}/g" "$RESULT_FILE"
else
    cat "$RESULT_FILE"
fi
