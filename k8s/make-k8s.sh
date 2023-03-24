#!/usr/bin/env bash

##  Импортируем переменные --------------------##
source ./k8s-vars.txt

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
##---------------------------------------------##

##  Подготовка всех хостов кластера
echo "Подготовка всех хостов кластера"
for val in $(seq 0 $NALL);do
   NODE=$(echo "${ALLHOSTS[$val]}" | awk '{print $1}')
   echo " "
   echo "----------------------------------------------------"
   echo "Готовим ноду: "$NODE
   echo "----------------------------------------------------"
   ssh-keyscan -H $NODE >> ~/.ssh/known_hosts
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
done
##---------------------------------------------##


##  Инициализация кластера на первом мастере --##
FIRSTMASTER=$(echo ${MASTERS[0]} | awk '{print $1}')
echo " "
echo "Инициализация кластера на первом мастере"
echo "Мастер нода: " $FIRSTMASTER
ssh -t $SSHUSER@$FIRSTMASTER -i $SSHKEY "
sudo kubeadm init --control-plane-endpoint "${BALANSER}:${BALANCERPORT}" --upload-certs --pod-network-cidr=10.244.0.0/16
sleep 60
sudo rm -rf \$HOME/.kube
mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
sed -i \"s/kubernetes-admin@kubernetes/k8s@kick/g\" \$HOME/.kube/config
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/canal.yaml -O
kubectl apply -f canal.yaml
sleep 90
echo CERTKEY=\$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1) > ~/tokens
echo DISCTOKCACERT=\$(sudo openssl x509 -in /etc/kubernetes/pki/ca.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print \$2}') >> ~/tokens
echo K8STOKEN=\$(sudo kubeadm token create --ttl 0) >> ~/tokens
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all node.kubernetes.io/not-ready:NoSchedule-
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
"
scp -i $SSHKEY $SSHUSER@$FIRSTMASTER:~/tokens ./tokens   
source ./tokens
scp -i $SSHKEY $SSHUSER@$FIRSTMASTER:~/.kube/config $HOME/.kube/config.kick
echo " "
echo "----------------------------------------------------"
##  --discovery-token-ca-cert-hash  =  sudo openssl x509 -in /etc/kubernetes/pki/ca.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $2}'
##  --certificate-key  =  sudo kubeadm init phase upload-certs --upload-certs | tail -n 1 
##  --token   =  sudo kubeadm token create
##---------------------------------------------##



##  Команды на остальных мастерах
echo " "
echo "Инициализация кластера на остальных мастерах"
for val in $(seq 1 $NMST);do
   NODE=$(echo "${MASTERS[$val]}" | awk '{print $1}')
   echo "Мастер нода: "$NODE
   ssh -i $SSHKEY -t $SSHUSER@$NODE "sudo kubeadm join ${BALANSER}:${BALANCERPORT} --token ${K8STOKEN} --discovery-token-ca-cert-hash sha256:${DISCTOKCACERT} --control-plane --certificate-key ${CERTKEY}"
   sleep 30
   echo " "
   echo "----------------------------------------------------"
done
##---------------------------------------------##



##  Команды на воркер-нодах
echo " "
echo "Инициализация кластера на воркер-нодах"
for val in $(seq 0 $NWRK);do
   NODE=$(echo "${WORKERS[$val]}" | awk '{print $1}')
   echo "Воркер нода: "$NODE
   ssh -i $SSHKEY -t $SSHUSER@$NODE "sudo kubeadm join ${BALANSER}:${BALANCERPORT} --token ${K8STOKEN} --discovery-token-ca-cert-hash sha256:${DISCTOKCACERT}"
   sleep 30
   echo " "
   echo "----------------------------------------------------"
done
##---------------------------------------------##


##  Роли и taint ------------------------------##
echo " "
echo "Правим роли и чистим taint"
for val in $(seq 0 $NMST);do
   NODE=$(echo "${MASTERS[$val]}" | awk '{print $2}')
   ssh -i $SSHKEY -t $SSHUSER@$FIRSTMASTER "kubectl label node $NODE node-role.kubernetes.io/master=master"
done
for val in $(seq 0 $NWRK);do
   NODE=$(echo "${WORKERS[$val]}" | awk '{print $2}')
   ssh -i $SSHKEY -t $SSHUSER@$FIRSTMASTER "kubectl label node $NODE node-role.kubernetes.io/worker=worker"
done
ssh -i $SSHKEY -t $SSHUSER@$FIRSTMASTER "
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/worker-
kubectl taint nodes --all node.kubernetes.io/not-ready:NoSchedule-
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
"
echo " "
echo "----------------------------------------------------"
echo "Кластер собран"
echo "Конфиг сохранен в $HOME/.kube/config.kick"
echo "Чтобы получить доступ к кластеру с помощью kubectl можно выполнить 'export KUBECONFIG=\$KUBECONFIG:\$HOME/.kube/config.kick'"
