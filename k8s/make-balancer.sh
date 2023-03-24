#!/usr/bin/env bash

##  Импортируем переменные --------------------##
source ./k8s-vars.txt 

## Количество мастеров в кластере -1 ----------##
NMST=`expr ${#MASTERS[*]} - 1`
ssh-keyscan -H $BALANSER >> ~/.ssh/known_hosts
ssh -t -i $BALANSERSSHKEY $BALANSERSSHUSER@$BALANSER "
sudo apt remove -y haproxy
sudo rm -rf /etc/haproxy/haproxy.cfg
sudo apt update
sudo apt -y install haproxy
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
frontend k8s_frontend
    bind *:6443
    mode tcp
    option tcplog
    timeout client  1m
    default_backend k8s_backend

backend k8s_backend
    mode tcp
    option tcplog
    option log-health-checks
    option redispatch
    log global
    balance roundrobin
    timeout connect 10s
    timeout server 1m   
EOF
"
for val in $(seq 0 $NMST);do
   NODE=$(echo "${MASTERS[$val]}" | awk '{print $1}')
   NODENAME=$(echo "${MASTERS[$val]}" | awk '{print $2}')
   MYADDR=$(ssh -t -i $SSHKEY $SSHUSER@$NODE "ip address | grep eth | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'")
   ssh -i $BALANSERSSHKEY -t $BALANSERSSHUSER@$BALANSER "echo  '    server $NODENAME ${MYADDR//[$'\t\r\n ']}:6443 check' | sudo tee -a /etc/haproxy/haproxy.cfg"
done
ssh -i $BALANSERSSHKEY -t $BALANSERSSHUSER@$BALANSER "sudo systemctl restart haproxy"
