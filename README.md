
# Vagrantfile and Scripts to Automate Kubernetes Setup using Kubeadm [Development environment to change and test rapidly on multiple nodes]

The main purpose of this repositry to make it easy to test your local Kubernetes change on a distributed environoment.

To change source directory please edit `SOURCE` at `Vagrantfile`.

Directory `/var/run/kubernetes` is a shared directory on master node, and contains all the configs.

## Prerequisites

1. Working Vagrant setup
2. 8 Gig + RAM workstation as the Vms use 3 vCPUS and 4+ GB RAM

## For MAC/Linux Users

Latest version of Virtualbox for Mac/Linux can cause issues because you have to create/edit the /etc/vbox/networks.conf file and add:
<pre>* 0.0.0.0/0 ::/0</pre>

or run below commands

```shell
sudo mkdir -p /etc/vbox/
echo "* 0.0.0.0/0 ::/0" | sudo tee -a /etc/vbox/networks.conf
```

So that the host only networks can be in any range, not just 192.168.56.0/21 as described here:
https://discuss.hashicorp.com/t/vagrant-2-2-18-osx-11-6-cannot-create-private-network/30984/23

## Usage/Examples

To provision the cluster, execute the following commands.

```shell
git clone https://github.com/mhmxs/vagrant-kubeadm-kubernetes.git
cd vagrant-kubeadm-kubernetes
vagrant up
```

## Start Kubernetes,

Initial step is to apply this patch on your Kubernetes source:
Work on progress: https://github.com/kubernetes/kubernetes/issues/115319

```diff
diff --git a/hack/local-up-cluster.sh b/hack/local-up-cluster.sh
index 20355a5074d..2426955706f 100755
--- a/hack/local-up-cluster.sh
+++ b/hack/local-up-cluster.sh
@@ -36,6 +36,7 @@ KUBELET_IMAGE=${KUBELET_IMAGE:-""}
 FAIL_SWAP_ON=${FAIL_SWAP_ON:-"false"}
 # Name of the dns addon, eg: "kube-dns" or "coredns"
 DNS_ADDON=${DNS_ADDON:-"coredns"}
+POD_CIDR=${POD_CIDR:-10.88.0.0/16}
 CLUSTER_CIDR=${CLUSTER_CIDR:-10.1.0.0/16}
 SERVICE_CLUSTER_IP_RANGE=${SERVICE_CLUSTER_IP_RANGE:-10.0.0.0/24}
 FIRST_SERVICE_CLUSTER_IP=${FIRST_SERVICE_CLUSTER_IP:-10.0.0.1}
@@ -547,6 +548,7 @@ EOF
       "${node_port_range}" \
       --v="${LOG_LEVEL}" \
       --vmodule="${LOG_SPEC}" \
+      --enable-bootstrap-token-auth \
       --audit-policy-file="${AUDIT_POLICY_FILE}" \
       --audit-log-path="${LOG_DIR}/kube-apiserver-audit.log" \
       --authorization-webhook-config-file="${AUTHORIZATION_WEBHOOK_CONFIG_FILE}" \
@@ -844,6 +846,7 @@ clientConnection:
   kubeconfig: ${CERT_DIR}/kube-proxy.kubeconfig
 hostnameOverride: ${HOSTNAME_OVERRIDE}
 mode: ${KUBE_PROXY_MODE}
+clusterCIDR: ${CLUSTER_CIDR}
 conntrack:
 # Skip setting sysctl value "net.netfilter.nf_conntrack_max"
   maxPerCore: 0
@@ -1063,7 +1066,7 @@ function install_cni {
         "type": "host-local",
         "ranges": [
           [{
-            "subnet": "10.88.0.0/16"
+            "subnet": "${POD_CIDR}"
           }],
           [{
             "subnet": "2001:4860:4860::/64"
```

Next step is to compile Kubernetes on your host machine or in the VM (should be slow).

```shell
(cd kubernetes-git-repository ; make all)
vagrant ssh master
start
```
 or

```shell
vagrant ssh master
curl -L https://go.dev/dl/go1.19.5.linux-amd64.tar.gz | tar xz -C /opt
TMPDIR=/tmp make all
start
```

## Start CNI plugin,

This is a manual step at the moment, execute once pre cluster.

```shell
vagrant ssh master
network
```

## Generate Join config,

```shell
vagrant ssh master
join
```

## Join a member,

```shell
vagrant ssh node01
member
```

## To shutdown the cluster,

```shell
vagrant halt
```

## To restart the cluster,

```shell
vagrant up
```

## To destroy the cluster,

```shell
vagrant destroy -f
```
