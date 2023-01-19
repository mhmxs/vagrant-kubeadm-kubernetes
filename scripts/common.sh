#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

: ${SOURCE? required}
: ${KUBE_VERSION? required}

sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved

rm -f /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
domain mshome.net
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
EOF

sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

sudo apt-get update -y

sudo apt-get install -y apt-transport-https ca-certificates curl jq socat conntrack runc net-tools

wget https://github.com/containerd/containerd/releases/download/v1.6.8/containerd-1.6.8-linux-amd64.tar.gz
sudo tar Czxvf /usr/local containerd-1.6.8-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mv containerd.service /usr/lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.26.0/crictl-v1.26.0-linux-amd64.tar.gz
sudo tar zxvf crictl-v1.26.0-linux-amd64.tar.gz -C /usr/local/bin

if [ -n ${MASTER} ]; then
    mkdir -p /var/run/kubernetes
    sudo apt install -y nfs-kernel-server
    cat <<EOF > /etc/exports
/var/run/kubernetes  192.168.56.0/24(rw,sync,no_subtree_check,all_squash,insecure)
EOF
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server make

    curl -L https://go.dev/dl/go1.19.5.linux-amd64.tar.gz | sudo tar xz -C /opt

    curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.3/cfssl-certinfo_1.6.3_linux_amd64 | sudo tee /usr/local/bin/cfssl 1>/dev/null
    sudo chmod +x /usr/local/bin/cfssl
else
    sudo apt install -y nfs-common
fi

cat <<EOF >> /home/vagrant/.bashrc
sudo su
EOF

cat <<EOF >> /root/.bashrc
modprobe br_netfilter

alias k=kubectl
export NET_PLUGIN=cni
export ETCD_HOST=192.168.56.10
export ALLOW_PRIVILEGED=1
export API_HOST=192.168.56.10
export KUBE_CONTROLLERS="*,bootstrapsigner,tokencleaner"
export KUBECONFIG=/var/run/kubernetes/admin.kubeconfig
export WHAT="cmd/kube-proxy cmd/kube-apiserver cmd/kube-controller-manager cmd/kubelet cmd/kubeadm cmd/kube-scheduler cmd/kubectl cmd/kubectl-convert"
export GOPATH=/vagrant/github.com/kubernetes/kubernetes
export GOROOT=/opt/go
export PATH=/opt/go/bin:${SOURCE}/third_party:${SOURCE}/third_party/etcd:${SOURCE}/_output/local/bin/linux/amd64:${PATH}

sudo() {
    echo \$@
}

start() {
    HOSTNAME_OVERRIDE=master-node ./hack/local-up-cluster.sh -O
}

join() {
    cp -f /tmp/\$(ls /tmp -t | grep "local-up-cluster.sh." | head -1)/* /var/run/kubernetes

    cat <<EOFI | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kubeadm:bootstrap-signer-clusterinfo
  namespace: kube-public
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kubeadm:bootstrap-signer-clusterinfo
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:anonymous
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kubeadm:bootstrap-signer-clusterinfo
  namespace: kube-public
rules:
- apiGroups:
  - ''
  resources:
  - configmaps
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubelet:operate
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubelet:operate
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:anonymous
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubelet:operate
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
EOFI

    cat <<EOFI > /var/run/kubernetes/kubeconfig
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: \$(base64 -iw0 /var/run/kubernetes/server-ca.crt)
    server: https://192.168.56.10:6443/
  name: ''
contexts: []
current-context: ''
kind: Config
preferences: {}
users: []
EOFI
    kubectl delete cm -n kube-public cluster-info |:
    kubectl create cm -n kube-public --from-file=/var/run/kubernetes/kubeconfig cluster-info

    sed "s/master-node/''/" /var/run/kubernetes/kube-proxy.yaml > /var/run/kubernetes/config.conf
    kubectl delete cm -n kube-system kube-proxy |:
    kubectl create cm -n kube-system --from-file=/var/run/kubernetes/config.conf kube-proxy

    cp -f /var/run/kubernetes/kubelet.yaml /var/run/kubernetes/kubelet
    kubectl delete cm -n kube-system kubelet-config |:
    kubectl create cm -n kube-system --from-file=/var/run/kubernetes/kubelet kubelet-config

    cat <<EOFI > /var/run/kubernetes/ClusterConfiguration
apiServer:
  timeoutForControlPlane: 2m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: local-up-cluster
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: ${KUBE_VERSION}
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.0.0.1/12
scheduler: {}
EOFI
    kubectl delete cm -n kube-system kubeadm-config |:
    kubectl create cm -n kube-system --from-file=/var/run/kubernetes/ClusterConfiguration kubeadm-config

    kubeadm token create --print-join-command > /var/run/kubernetes/join.sh

    token_id="\$(cat /var/run/kubernetes/join.sh | awk '{print \$5}' | cut -d. -f1)"

    cat <<EOFI | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kubeadm:bootstrap-signer-kubeadm-config
  namespace: kube-system
rules:
- apiGroups:
  - ''
  resourceNames:
  - kubeadm-config
  - kube-proxy
  - kubelet-config
  resources:
  - configmaps
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kubeadm:bootstrap-signer-kubeadm-config
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kubeadm:bootstrap-signer-kubeadm-config
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:bootstrap:\${token_id}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeadm:bootstrap-signer-kubeadm-config
rules:
- apiGroups:
  - ''
  resources:
  - nodes
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:bootstrap-signer-kubeadm-config
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubeadm:bootstrap-signer-kubeadm-config
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:bootstrap:\${token_id}
EOFI

    exportfs -a

    chmod -R a+rw /var/run/kubernetes/*
}

network() {
  curl -Ls https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml | sed "s/244/88/" | kubectl apply -f -
}

member() {
  mkdir -p /var/run/kubernetes ; mount | grep /var/run/kubernetes 1>/dev/null || mount 192.168.56.10:/var/run/kubernetes /var/run/kubernetes

  cat <<EOFI > /etc/systemd/system/kubelet.service
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/vagrant/github.com/kubernetes/kubernetes/_output/local/bin/linux/amd64/kubelet \\
--hostname-override=$(hostname) \\
--pod-cidr 10.88.${NODE}.0/16 \\
--register-node=true \\
--v=3 \\
--bootstrap-kubeconfig=/var/run/kubernetes/admin.kubeconfig \\
--kubeconfig=/var/run/kubernetes/admin.kubeconfig \\
--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
--client-ca-file=/var/run/kubernetes/client-ca.crt \\
--config=/var/run/kubernetes/kubelet.yaml
Restart=no
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFI

  systemctl daemon-reload

  sh /var/run/kubernetes/join.sh
}

cd ${SOURCE}
EOF
