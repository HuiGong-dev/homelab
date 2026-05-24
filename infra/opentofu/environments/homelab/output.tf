output "adguard_vm_ip" {
  value = split("/", local.adguard_ip_config)[0]
}

output "adguard_vm_id" {
  value = module.adguard.vm_id
}

output "adguard_vm_name" {
  value = module.adguard.name
}
