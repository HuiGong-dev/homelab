output "adguard_vm_ip" {
  value = module.adguard.cloud_init_ipv4_address
}

output "adguard_vm_id" {
  value = module.adguard.vm_id
}

output "adguard_vm_name" {
  value = module.adguard.name
}
