output "vm_id" {
  description = "VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.this.name
}

output "ipv4_addresses" {
  description = "IPv4 addresses reported by the guest agent"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}