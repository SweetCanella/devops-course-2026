#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
local desc="$1" expected="$2" actual="$3"
if [[ "$actual" == "$expected" ]]; then
echo " [OK] $desc"; ((PASS++))
else
echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')";
((FAIL++))
fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
port="$(sudo sshd -T | awk '/^port /{print $2; exit}')"
if [[ "$port" != "22" ]]; then
echo " [OK] Порт службы SSH отличен от 22"; ((PASS++))
else
echo " [FAIL] Порт службы SSH отличен от 22 (ожидалось: значение, отличное от '22', получено: '$port')";
((FAIL++))
fi
check "Число попыток аутентификации равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries /{print $2; exit}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
incoming="$(sudo ufw status verbose | awk -F'[: ]+' '/^Default:/{print $2; exit}')"
check "Политика по умолчанию для входящего трафика — deny" "deny" "$incoming"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
sudo nginx -t >/dev/null 2>&1
check "Конфигурация nginx корректна" "0" "$?"
sudo openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1
check "Сертификат действителен ещё не менее 30 дней" "0" "$?"
writable="$(find /var/www/devops-site -perm -o+w | wc -l | tr -d ' ')"
keymode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
if [[ "$writable" == "0" && "$keymode" == "600" ]]; then
  web_access="ok"
else
  web_access="files=${writable},key=${keymode}"
fi
check "Нет файлов с правом записи для всех, ключ имеет права 600" "ok" "$web_access"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
