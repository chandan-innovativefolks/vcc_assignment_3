Vagrant.configure("2") do |config|
  config.vm.box = "net9/ubuntu-24.04-arm64"
  config.vm.hostname = "local-vm"

  # ---- Bridged Network (DEFAULT) ----
  config.vm.network "public_network", bridge: "en0: Wi-Fi"

  config.vm.network "forwarded_port", guest: 5001, host: 5001
  config.vm.network "forwarded_port", guest: 9090, host: 9090
  config.vm.network "forwarded_port", guest: 3000, host: 3000
  config.vm.network "forwarded_port", guest: 9100, host: 9100

  config.vm.provider "virtualbox" do |vb|
    vb.name = "vcc-local-vm"
    vb.memory = 4096
    vb.cpus = 2
  end

  config.vm.provision "shell", path: "provision.sh"
end