NUM_WORKER_NODES=1
IP_NW="192.168.56."
IP_START=10
KUBE_VERSION="1.27.0"
SOURCE="/vagrant/github.com/kubernetes/kubernetes"

Vagrant.configure("2") do |config|
  config.vm.provision "shell", env: {"IP_NW" => IP_NW, "IP_START" => IP_START}, inline: <<-SHELL
      apt-get update -y
      echo "$IP_NW$((IP_START)) master-node" >> /etc/hosts
      echo "$IP_NW$((IP_START+1)) worker-node01" >> /etc/hosts
      echo "$IP_NW$((IP_START+2)) worker-node02" >> /etc/hosts
  SHELL

  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_check_update = true

  config.vm.define "master" do |master|
    # master.vm.box = "bento/ubuntu-18.04"
    master.vm.hostname = "master-node"
    master.vm.network "private_network", ip: IP_NW + "#{IP_START}"
    master.vm.provider "virtualbox" do |vb|
        vb.memory = 4048
        vb.cpus = 4
    end
    master.vm.provision "shell", path: "scripts/common.sh", env: {"MASTER" => true, "SOURCE" => SOURCE, "NODE" => 0, "KUBE_VERSION" => KUBE_VERSION}
  end

  (1..NUM_WORKER_NODES).each do |i|

  config.vm.define "node0#{i}" do |node|
    node.vm.hostname = "worker-node0#{i}"
    node.vm.network "private_network", ip: IP_NW + "#{IP_START + i}"
    node.vm.provider "virtualbox" do |vb|
        vb.memory = 2048
        vb.cpus = 2
    end
    node.vm.provision "shell", path: "scripts/common.sh", env: {"MASTER" => "", "SOURCE" => SOURCE, "NODE" => i, "KUBE_VERSION" => KUBE_VERSION}
  end

  end
end 
