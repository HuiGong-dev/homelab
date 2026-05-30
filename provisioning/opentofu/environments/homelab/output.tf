output "adguard_vm_ip" {
  value = module.adguard.cloud_init_ipv4_address
}

output "adguard_vm_id" {
  value = module.adguard.vm_id
}

output "adguard_vm_name" {
  value = module.adguard.name
}

output "k3s_server_01_vm_ip" {
  value = module.k3s-server-01.cloud_init_ipv4_address
}

output "k3s_server_01_vm_id" {
  value = module.k3s-server-01.vm_id
}

output "k3s_server_01_vm_name" {
  value = module.k3s-server-01.name
}

output "nas_vm_ip" {
  value = module.nas-vm.cloud_init_ipv4_address
}

output "nas_vm_id" {
  value = module.nas-vm.vm_id
}

output "nas_vm_name" {
  value = module.nas-vm.name
}
