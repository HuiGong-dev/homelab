output "test_vm_ip" {
  value = split("/", local.test_vm_01_ip_config)[0]
}

output "test_vm_id" {
  value = module.test_vm_01.vm_id
}

output "test_vm_name" {
  value = module.test_vm_01.name
}
