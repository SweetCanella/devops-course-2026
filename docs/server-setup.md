# Конфигурация виртуальной машины devops-vm

Документ описывает итоговое состояние после практической работы № 5.
По нему конфигурация восстанавливается со снимка `01-clean-install`.

## 1. Параметры машины

- Средство виртуализации: VirtualBox 7.2
- Имя: `devops-vm`
- Гостевая система: Ubuntu Server 24.04.5 LTS, 64-bit
- Память: 2048 МБ
- Процессор: 2 ядра
- Диск: 25 ГБ, динамический VDI
- Имя узла: `devops-vm`
- Полное имя: `devops-vm.devops.local`

Полное имя восстанавливается так:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

## 2. Сетевые интерфейсы

- Адаптер 1, NAT, интерфейс `enp0s3`, адрес `10.0.2.15/24`. Нужен для исходящего доступа в интернет и к репозиториям пакетов. С хоста этот адрес напрямую не открывается.
- Адаптер 2, Host-only (`VirtualBox Host-Only Ethernet Adapter`), интерфейс `enp0s8`, адрес `192.168.56.101/24`. Нужен для обращения к службам машины с хоста, в том числе к веб-серверу в работе № 6. Адрес хоста в этом сегменте: `192.168.56.1`.

На хосте Windows в `C:\Windows\System32\drivers\etc\hosts` добавлена строка:

```text
192.168.56.101 devops.local
```

Сеть `192.168.56.0/24` пересекается с туннелем AmneziaVPN. Пока туннель включён, пакеты к `192.168.56.101` не доходят до виртуальной машины. Вход `ssh devops` идёт на `127.0.0.1` и от этого туннеля не зависит.

## 3. Правило проброса портов

Адаптер NAT, правило `ssh`:

- протокол TCP
- адрес хоста: `127.0.0.1`
- порт хоста: `2222`
- адрес гостя: не задан
- порт гостя: `2222`

До усиления SSH порт гостя был `22`. После смены порта службы проброс изменён на `2222`.

## 4. Учётные записи

- `student` — учётная запись установки, входит в группу `sudo`. После директивы `AllowUsers devops` вход по SSH для неё закрыт.
- `devops` — рабочая учётная запись администратора. Группы: `devops`, `sudo`, `users`. Вход по SSH только ключом. Пароль нужен для `sudo`.

Ключ создан отдельно от ключа доступа к репозиториям:

```powershell
ssh-keygen -t ed25519 -C "devops-vm-key" -f $env:USERPROFILE\.ssh\devops_vm
```

Открытый ключ лежит в `/home/devops/.ssh/authorized_keys`. Права: каталог `.ssh` — `700`, файл `authorized_keys` — `600`.

Фрагмент `C:\Users\baram\.ssh\config`:

```text
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Проверка: `ssh devops` открывает сессию без запроса пароля.

Отпечаток ключа хоста: `SHA256:ok3bYOd4J7ic5rkp8Ytnlvmu/mgDdSjTq/D5HD2/NSs`.

## 5. Служба SSH

Служба слушает порт `2222` на `0.0.0.0` и `[::]`. Сокетная активация отключена, работает юнит `ssh.service`:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```

Основной файл `/etc/ssh/sshd_config` не изменялся, его копия: `/etc/ssh/sshd_config.backup`.
Действующие ограничения записаны в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована. Иначе она перебивает файл `99-hardening.conf`, потому что каталог читается по алфавиту и действует первое значение директивы.

Проверка до перезапуска: `sudo sshd -t`, затем `sudo sshd -T`.

## 6. Правила межсетевого экрана

Политики: входящий трафик `deny`, исходящий `allow`.

Разрешающие правила созданы до `ufw enable`:

- `80/tcp` ALLOW, комментарий HTTP
- `443/tcp` ALLOW, комментарий HTTPS
- `2222/tcp` LIMIT, комментарий `SSH rate-limited`

Правило `ufw allow ssh` не используется: имя `ssh` в `/etc/services` означает порт 22, а служба слушает 2222.
Журнал UFW: `medium`. Запрос на `192.168.56.101:8080` блокируется. В записи `UFW BLOCK` поля `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

## 7. Снимки состояния

- `01-clean-install` — 13.11.2026 16:57, после установки и обновления системы, до учётной записи `devops`
- `02-keys-configured` — 13.11.2026 17:07, пользователь `devops` и вход по ключу
- `03-ssh-hardened` — 13.11.2026 17:19, усиленная конфигурация SSH и порт 2222

Межсетевой экран и полное имя узла настроены после снимка `03-ssh-hardened`.

- `04-nginx-https` — после установки Nginx, выпуска самоподписанного сертификата и включения HTTPS
- `05-docker-compose` — 13.11.2026 21:32, приложение и PostgreSQL в Docker Compose. Снимок сделан до публикации приложения через Nginx

## 8. Веб-сервер

Пакет `nginx` из репозитория Ubuntu, установленная версия `1.24.0`. Стандартный сайт отключён: симлинк `sites-enabled/default` удалён. Рабочая конфигурация — `/etc/nginx/sites-available/devops-site`, включена симлинком `/etc/nginx/sites-enabled/devops-site`.

Каталог ресурса `/var/www/devops-site`, владелец `devops:devops`. Каталог имеет права `755`, файлы — `644`. В каталоге лежат `index.html` и `404.html`.

Сертификат `/etc/ssl/certs/devops.crt`, владелец `root`, права `644`. Закрытый ключ `/etc/ssl/private/devops.key`, владелец `root`, права `600`. Ключ в репозиторий не копируется.

Сертификат самоподписанный, срок 365 суток: с `Nov 13 15:00:40 2026 GMT` по `Nov 13 15:00:40 2027 GMT`. В поле SAN указано `DNS:devops.local`.

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo nginx -t && sudo systemctl reload nginx
```

Порт 80 отвечает `301` и заголовком `Location: https://devops.local/...`. Порт 443 отдаёт ресурс. Заголовок HSTS не используется. Проверка конфигурации перед перезагрузкой: `sudo nginx -t`, затем `sudo systemctl reload nginx`, не `restart`.

В блоке HTTPS есть расположение для контейнера. Косая черта в конце `proxy_pass` убирает префикс `/app/`: запрос `/app/health` уходит приложению как `/health`. Статический каталог `/var/www/devops-site` при этом сохраняется.

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## 9. Контейнеризация

Docker Engine установлен из официального репозитория Docker, не из пакета `docker.io`. Версия Engine `29.9.3`, плагин Compose `v5.7.1`. Ключ лежит в `/etc/apt/keyrings/docker.asc`, источник пакетов — `/etc/apt/sources.list.d/docker.sources` для Ubuntu `noble`, компонент `stable`. Установлены пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` и `docker-compose-plugin`. Служба `docker` включена и активна.

В группе `docker` состоит пользователь `devops`. Другие учётные записи в эту группу не добавлялись: член группы может запустить контейнер с корнем диска машины и тем самым получить права root.

Проект на сервере: `/home/devops/app`. Образ приложения `devops-app:1.0` собирается из `Dockerfile` этого каталога и работает от пользователя `app`, не от root. Рядом описан сервис PostgreSQL `postgres:16-alpine`. Файл секретов `/home/devops/app/.env` создан только на сервере, права `600`. В репозитории есть только шаблон `app/.env.example` с заглушкой пароля. При доставке `rsync` файл `.env` исключается, иначе `--delete` удалил бы его.

Сеть проекта `app_backend`, тип bridge. Приложение обращается к СУБД по имени `db`. Том `app_db_data` подключён к `/var/lib/postgresql/data` и не удаляется командой `docker compose down`. Команда `docker compose down -v` удаляет том вместе с данными.

Порт приложения опубликован только на `127.0.0.1:5000`. Порт `5432` на сервере не публикуется. Публикация на `0.0.0.0` обходит правила UFW, потому что Docker добавляет DNAT в цепочку `iptables` раньше фильтра UFW. Привязка к `127.0.0.1` оставляет порт доступным только для Nginx на этой же машине.

Nginx принимает `https://devops.local/app/` и передаёт запрос на `http://127.0.0.1:5000/`. Если контейнер приложения остановлен, Nginx отвечает `502` и пишет в `/var/log/nginx/devops-site.error.log` строку `connect() failed (111: Connection refused) while connecting to upstream`.
