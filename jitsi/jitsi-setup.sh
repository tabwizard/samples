#!/usr/bin/env bash

## --- Переменные ---------------------------------------------#
##
## Версия сервиса Jitsi
JITSIVER=8252
## Внешний IP-адрес виртуальной машины
EXTERNALIP=91.239.27.148
## Доменное имя сервиса Jitsi
SITEURL=jitsi.pirozhkov-aa.ru
## Действительный email для получения Let's Encrypt сертификата
SITEMAIL=pirozhkov.a.a@yandex.ru
## Имя пользователя для доступа к виртуальной машине
SSHUSER=root
## Приватный ключ для доступа к виртуальной машине
SSHKEY=~/.ssh/serveroid/serveroid
## Таймзона сервиса Jitsi примеры https://ru.thetimenow.com/time-zones-abbreviations.php
JITSITIMEZONE=MSK
##-------------------------------------------------------------#

ssh-keyscan -H ${EXTERNALIP} >> ~/.ssh/known_hosts
ssh -t -i ${SSHKEY} ${SSHUSER}@${EXTERNALIP} "
apt update
apt install -y docker docker-compose mc curl
systemctl enable --now docker.service
curl -L https://github.com/jitsi/docker-jitsi-meet/archive/refs/tags/stable-${JITSIVER}.tar.gz > ./jitsi-meet-stable-${JITSIVER}.tar.gz
tar -xvf ./jitsi-meet-stable-${JITSIVER}.tar.gz
cd ./docker-jitsi-meet-stable-${JITSIVER}
cp env.example .env
./gen-passwords.sh
sed -i \
    -e \"s/HTTP_PORT=8000/HTTP_PORT=80/\" \
    -e \"s/HTTPS_PORT=8443/HTTPS_PORT=443\nENABLE_HTTP_REDIRECT=1/\" \
    -e \"s/TZ=UTC/TZ=${JITSITIMEZONE}/\" \
    -e \"s/#PUBLIC_URL=.*/PUBLIC_URL=https:\/\/${SITEURL}/\" \
    -e \"s/#JVB_ADVERTISE_IPS=.*/JVB_ADVERTISE_IPS=${EXTERNALIP}/\" \
    -e \"s/#ENABLE_LETSENCRYPT=.*/ENABLE_LETSENCRYPT=1/\" \
    -e \"s/#LETSENCRYPT_DOMAIN=.*/LETSENCRYPT_DOMAIN=${SITEURL}/\" \
    -e \"s/#LETSENCRYPT_EMAIL=.*/LETSENCRYPT_EMAIL=${SITEMAIL}/\" \
    -e \"s/#ENABLE_GUESTS=.*/ENABLE_GUESTS=1/\" \
    ./.env
mkdir -p ~/.jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

cat <<EOF >/etc/systemd/system/jitsi.service
[Unit]
Description=Jitsi server start in docker-compose
PartOf=docker.service
After=docker.service

[Service]
User=${SSHUSER}
Type=oneshot
RemainAfterExit=true
WorkingDirectory=\$PWD
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down --remove-orphans

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now jitsi.service
"

# https://jitsi.pirozhkov-aa.ru

# Сервис Jitsi гарантировано работает только в Chrome или Chromium
