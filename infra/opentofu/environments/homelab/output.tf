output "adguard_vm_ip" {
  value = split("/", local.adguard_ip_config)[0]
}

output "adguard_vm_id" {
  value = module.adguard_vm_01.vm_id
}

output "adguard_vm_name" {
  value = module.adguard_vm_01.name
}
