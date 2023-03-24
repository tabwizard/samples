#!/usr/bin/env bash
echo "Для добавления воркер-ноды запустить скрипт с параметрами - IP-address Hostname"
echo "Например:      add_worker.sh 192.168.223.1 new-worker1"
if (( $# < 2 )); then echo "Мало параметров"; exit 1; fi
##  Импортируем переменные --------------------##
source ./k8s-vars.txt
ssh-keyscan -H $1 >> ~/.ssh/known_hosts
##  Количество хостов в кластере -1 -----------##
NALL=`expr ${#ALLHOSTS[*]} - 1`
## Количество мастеров в кластере -1 ----------##
NMST=`expr ${#MASTERS[*]} - 1`
## Количество воркер-нод в кластере -1 --------##
NWRK=`expr ${#WORKERS[*]} - 1`

##  Список для добавления в /etc/hosts --------##
rm -rf ./tmphosts
for val in $(seq 0 $NALL);do
   NODE=$(echo "${ALLHOSTS[$val]}" | awk '{print $1}')
   NODENAME=$(echo "${ALLHOSTS[$val]}" | awk '{print $2}')
   MYADDR=$(ssh -t -i $SSHKEY $SSHUSER@$NODE "ip address | grep eth | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'")
   echo "${MYADDR//[$'\t\r\n ']} $NODENAME" >> ./tmphosts
done
MYADDR=$(ssh -t -i $SSHKEY $SSHUSER@$1 "ip address | grep eth | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'")
echo "${MYADDR//[$'\t\r\n ']} $2" >> ./tmphosts
##---------------------------------------------##


##  Добавляем новую воркер-ноду в /etc/hosts на все хосты кластера
echo "Добавляем новую воркер-ноду в /etc/hosts на все хосты кластера"
for val in $(seq 0 $NALL);do
   NODE=$(echo "${ALLHOSTS[$val]}" | awk '{print $1}')
   echo " "
   echo "----------------------------------------------------"
   echo "Добавляем на ноду: "$NODE
   echo "----------------------------------------------------"
   ssh -t -i $SSHKEY $SSHUSER@$NODE "echo ${MYADDR//[$'\t\r\n ']} $2 | sudo tee -a /etc/hosts"
echo " "
echo "----------------------------------------------------"
done
##---------------------------------------------##


##  Подготовка дополнительной воркер-ноды
echo "Подготовка дополнительной воркер-ноды"
NODE=$1
echo " "
echo "----------------------------------------------------"
echo "Готовим ноду: "$NODE
echo "----------------------------------------------------"
scp -i $SSHKEY ./tmphosts $SSHUSER@$NODE:~/
ssh -t -i $SSHKEY $SSHUSER@$NODE "
cat <<EOFF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOFF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOFE | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOFE
sudo sysctl --system
sudo rm -rf /etc/containerd
sudo apt-get update
sudo apt-mark unhold containerd kubelet kubeadm kubectl
sudo apt remove -y containerd
sudo apt-get -y install containerd
sudo apt-get -y install apt-transport-https ca-certificates curl software-properties-common gnupg curl mc sed original-awk
sudo apt-mark hold containerd kubelet kubeadm kubectl
sudo systemctl stop containerd
curl -L https://github.com/containerd/containerd/releases/download/v1.6.16/containerd-1.6.16-linux-amd64.tar.gz > containerd-1.6.16-linux-amd64.tar.gz
sudo tar -xvf containerd-1.6.16-linux-amd64.tar.gz -C /tmp ; yes | sudo cp -rf /tmp/bin/* /bin
sudo systemctl start containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i \"s/SystemdCgroup = false/SystemdCgroup = true/g\" /etc/containerd/config.toml
sudo systemctl restart containerd
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
cat <<EOFQ | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOFQ
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
cat ~/tmphosts | sudo tee -a /etc/hosts
sudo swapoff –a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo systemctl enable kubelet
"
echo " "
echo "----------------------------------------------------"
##---------------------------------------------##

##  Получаем ключи кластера
source ./tokens

echo " "
echo "Инициализация кластера на дополнительной воркер-ноде"
echo "Дополнительная воркер-нода: "$NODE
ssh -i $SSHKEY -t $SSHUSER@$NODE "sudo kubeadm join ${BALANSER}:${BALANCERPORT} --token ${K8STOKEN} --discovery-token-ca-cert-hash sha256:${DISCTOKCACERT}"
sleep 30
echo " "
echo "----------------------------------------------------"
##---------------------------------------------##


##  Роли и taint ------------------------------##
FIRSTMASTER=$(echo ${MASTERS[0]} | awk '{print $1}')
echo " "
echo "Правим роли и чистим taint"
ssh -i $SSHKEY -t $SSHUSER@$FIRSTMASTER "kubectl label node $2 node-role.kubernetes.io/worker=worker"
ssh -i $SSHKEY -t $SSHUSER@$FIRSTMASTER "
kubectl taint nodes --all node-role.kubernetes.io/worker-
kubectl taint nodes --all node.kubernetes.io/not-ready:NoSchedule-
"
echo " "
echo "----------------------------------------------------"
echo "Дополнительная воркер-нода добавлена"  
echo " "
echo "После успешного добавления ноды не забудьте добавить ее в k8s-vars.txt"
