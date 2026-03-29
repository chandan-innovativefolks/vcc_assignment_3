# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Apple Silicon + VirtualBox: the default ubuntu/jammy64 VirtualBox box is amd64-only;
# VirtualBox on ARM Macs cannot run x86_64 guests. Use an Intel host/Linux, Parallels/VMware
# with an arm64 box, or another workflow (e.g. Docker).

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "local-vm"

  config.vm.network "private_network", ip: "192.168.56.10"

  # Port forwarding for application and monitoring
  # Host 5001: macOS often reserves 5000 for AirPlay Receiver (Control Center)
  config.vm.network "forwarded_port", guest: 5000, host: 5001, host_ip: "127.0.0.1"   # Flask app
  config.vm.network "forwarded_port", guest: 9090, host: 9090   # Prometheus
  config.vm.network "forwarded_port", guest: 3000, host: 3000   # Grafana
  config.vm.network "forwarded_port", guest: 9100, host: 9100   # Node Exporter

  config.vm.provider "virtualbox" do |vb|
    vb.name = "vcc-local-vm"
    vb.memory = "2048"
    vb.cpus = 2
  end

  config.vm.provision "shell", path: "provision.sh"
end
