#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

: ${SOURCE? required}
: ${KUBE_VERSION? required}
: ${MASTER_IP? required}
: ${MASTER_NAME? required}
: ${NODE_IP? required}
: ${NODE_NAME? required}

apt update -y
apt install -y apt-transport-https ca-certificates curl socat conntrack runc net-tools

systemctl disable --now ufw
ufw reset ||:
apt remove -y ufw

systemctl disable systemd-resolved
systemctl stop systemd-resolved
rm -f /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

modprobe overlay
modprobe br_netfilter
echo "br_netfilter" >> /etc/modules
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

curl -LO https://github.com/containerd/containerd/releases/download/v1.6.8/containerd-1.6.8-linux-amd64.tar.gz
tar Czxvf /usr/local containerd-1.6.8-linux-amd64.tar.gz
curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mv containerd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd

curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.26.0/crictl-v1.26.0-linux-amd64.tar.gz
tar zxvf crictl-v1.26.0-linux-amd64.tar.gz -C /usr/local/bin

if [[ $(hostname) = ${MASTER_NAME} ]]; then
    mkdir -p /var/run/kubernetes
    apt install -y nfs-kernel-server make
    cat <<EOF > /etc/exports
/var/run/kubernetes  ${MASTER_IP}/24(rw,sync,no_subtree_check,all_squash,insecure)
EOF
    exportfs -a
    systemctl restart nfs-kernel-server

    curl -Lo /usr/local/bin/cfssl https://github.com/cloudflare/cfssl/releases/download/v1.5.0/cfssl_1.5.0_linux_amd64
    chmod +x /usr/local/bin/cfssl

    curl -Lo /usr/local/bin/cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.5.0/cfssljson_1.5.0_linux_amd64
    chmod +x /usr/local/bin/cfssljson
else
    apt install -y nfs-common
fi

cat <<EOF >> /home/vagrant/.bashrc
(cd ${SOURCE} ; sudo su) ; exit
EOF

cat <<EOF >> /root/.bashrc
alias k=kubectl

export CNI_CONFIG_DIR=/tmp
export LOG_LEVEL=4
export ALLOW_PRIVILEGED=1
export ETCD_HOST=${MASTER_IP}
export API_HOST=${MASTER_IP}
export API_HOST_IP=${MASTER_IP}
export ADVERTISE_ADDRESS=${MASTER_IP}
export API_CORS_ALLOWED_ORIGINS=".*"
export KUBE_CONTROLLERS="*,bootstrapsigner,tokencleaner"
export KUBE_ENABLE_NODELOCAL_DNS=true
export WHAT="cmd/kube-proxy cmd/kube-apiserver cmd/kube-controller-manager cmd/kubelet cmd/kubeadm cmd/kube-scheduler cmd/kubectl cmd/kubectl-convert"
export POD_CIDR="172.16.0.0/16"
export CLUSTER_CIDR="172.0.0.0/8"
export SERVICE_CLUSTER_IP_RANGE="172.17.0.0/18"
export FIRST_SERVICE_CLUSTER_IP="172.17.0.1"
export KUBE_DNS_SERVER_IP="172.17.63.254"
export KUBECONFIG=/var/run/kubernetes/admin.kubeconfig
export GOPATH=/vagrant/github.com/kubernetes/kubernetes
export GOROOT=/opt/go
export PATH=/opt/go/bin:${SOURCE}/third_party:${SOURCE}/third_party/etcd:${SOURCE}/_output/local/bin/linux/amd64:${PATH}

iptables -t nat -A PREROUTING -i cni0 -d ${SERVICE_CLUSTER_IP_RANGE} -j DNAT --to-destination 10.88.0.1

sudo() {
    \$@
}

alias install-docker="apt install -y docker.io && systemctl start docker && systemctl disable docker"

start() {
    rm -rf /var/run/kubernetes/* ||:
    KUBELET_HOST=${MASTER_IP} HOSTNAME_OVERRIDE=${MASTER_NAME} ./hack/local-up-cluster.sh -O
}

alias network=calico

falnnel() {
  kubectl patch node ${NODE_NAME} -p '{"spec":{"podCIDR":"'\${POD_CIDR}'"}}'
  curl -Ls https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml | \
    sed 's/- --ip-masq/- --ip-masq\n        - --iface=enp0s8/' | \
    sed 's|10.244.0.0/16|'\${POD_CIDR}'|' | \
    kubectl apply -f -
}

alias calicoctl="kubectl exec -i -n kube-system calicoctl -- /calicoctl"

calico() {
  curl -Ls https://docs.projectcalico.org/manifests/calico.yaml | \
    sed 's/value: "Always"/value: "Never"/' | \
    sed 's/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/' | \
    sed 's|#   value: "192.168.0.0/16"|  value: "'\${POD_CIDR}'"|' | \
    kubectl apply -f -
  kubectl apply -f https://docs.projectcalico.org/manifests/calicoctl.yaml
}

bgp() {
  cat <<EOFI | kubectl apply -f -
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  bindMode: NodeIP
  nodeToNodeMeshEnabled: true
  asNumber: 63400
  serviceClusterIPs:
  - cidr: \${SERVICE_CLUSTER_IP_RANGE}
---
kind: BGPPeer
apiVersion: crd.projectcalico.org/v1
metadata:
  name: peer-to-peer
spec:
  nodeSelector: all()
  peerSelector: all()
EOFI
}

join() {
    last=\$(ls /tmp -t | grep "local-up-cluster.sh." | head -1)
    if [[ "\${last}" ]]; then
      cp -rf /tmp/\${last}/* /var/run/kubernetes
    else
      cp -rf /tmp/kube* /var/run/kubernetes
    fi

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
    server: https://${MASTER_IP}:6443/
  name: ''
contexts: []
current-context: ''
kind: Config
preferences: {}
users: []
EOFI
    kubectl delete cm -n kube-public cluster-info |:
    kubectl create cm -n kube-public --from-file=/var/run/kubernetes/kubeconfig cluster-info

    cat /var/run/kubernetes/kube-proxy.yaml | sed -e "s/${MASTER_NAME}/''/" -e "s/${MASTER_IP}/${NODE_IP}/" > /var/run/kubernetes/config.conf
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
imageRepository: registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: ${KUBE_VERSION}
networking:
  dnsDomain: cluster.local
  serviceSubnet: \${SERVICE_CLUSTER_IP_RANGE}
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

member() {
  mkdir -p /var/run/kubernetes ; mount | grep /var/run/kubernetes 1>/dev/null || mount ${MASTER_IP}:/var/run/kubernetes /var/run/kubernetes

  cat <<EOFI > /etc/systemd/system/kube-proxy.service
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/vagrant/github.com/kubernetes/kubernetes/_output/local/bin/linux/amd64/kube-proxy \\
--v=3 \\
--config=/var/run/kubernetes/config.conf \\
--master="https://${MASTER_IP}:6443"
Restart=on-failure
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFI

  cat <<EOFI > /etc/systemd/system/kubelet.service
[Unit]
Wants=kube-proxy
After=kube-proxy

[Service]
ExecStart=/vagrant/github.com/kubernetes/kubernetes/_output/local/bin/linux/amd64/kubelet \\
--address="${NODE_IP}" \\
--hostname-override=$(hostname) \\
--pod-cidr=\${POD_CIDR} \\
--node-ip="${NODE_IP}" \\
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

  systemctl restart kube-proxy

  rm -rf /etc/kubernetes

  sh /var/run/kubernetes/join.sh
}

EOF
