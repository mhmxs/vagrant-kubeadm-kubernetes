NUM_WORKER_NODES=1
IP_NW="192.168.56."
IP_START=10
KUBE_VERSION="1.27.0"
SOURCE="/vagrant/github.com/kubernetes/kubernetes"

Vagrant.configure("2") do |config|
  config.vm.provision "shell", env: {"IP_NW" => IP_NW, "IP_START" => IP_START}, inline: <<-SHELL
      sed -i "s/$(grep '127.0.2.1' /etc/hosts)//" /etc/hosts
      echo "$IP_NW$((IP_START)) master-node" >> /etc/hosts
      echo "$IP_NW$((IP_START+1)) worker-node01" >> /etc/hosts
      echo "$IP_NW$((IP_START+2)) worker-node02" >> /etc/hosts
  SHELL

  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = true

  config.vm.define "master" do |master|
    master.vm.hostname = "master-node"
    master.vm.network "private_network", ip: IP_NW + "#{IP_START}"
    master.vm.provider "virtualbox" do |vb|
        vb.memory = 2048
        vb.cpus = 4
    end
    master.vm.provision "shell", path: "scripts/common.sh", env: {
      "SOURCE" => SOURCE,
      "NODE" => 0,
      "KUBE_VERSION" => KUBE_VERSION,
      "MASTER_IP" => "192.168.56.10",
      "MASTER_NAME" => "master-node",
      "POD_CIDR" => "192.168.0.0/16"
    }
  end

  (1..NUM_WORKER_NODES).each do |i|
    config.vm.define "node0#{i}" do |node|
      node.vm.hostname = "worker-node0#{i}"
      node.vm.network "private_network", ip: IP_NW + "#{IP_START + i}"
      node.vm.provider "virtualbox" do |vb|
          vb.memory = 2048
          vb.cpus = 2
      end
      node.vm.provision "shell", path: "scripts/common.sh", env: {
        "SOURCE" => SOURCE,
        "NODE" => i,
        "KUBE_VERSION" => KUBE_VERSION,
        "MASTER_IP" => "192.168.56.10",
        "MASTER_NAME" => "master-node",
        "POD_CIDR" => "192.168.0.0/16"
      }
    end

  end
end 
