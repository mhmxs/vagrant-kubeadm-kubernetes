
# Vagrantfile and Scripts to Automate Kubernetes Setup using Kubeadm [Development environment to change and test rapidly on multiple nodes]

[WIP] The main purpose of this repositry to make it easy to test your local Kubernetes change on a distributed environoment.

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

First step is to compile Kubernetes on your host machine (Build system isn't included)

```shell
(cd kubernetes-git-repository ; make all)
vagrant ssh master
start
```

## Generate Join config,

```shell
vagrant ssh master
join
```

## Join member,

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
