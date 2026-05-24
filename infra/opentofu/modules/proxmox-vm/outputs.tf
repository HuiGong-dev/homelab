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

output "cloud_init_ipv4_address" {
  description = "IPv4 address configured through cloud-init, or null when DHCP is used"
  value       = var.ip_config == "dhcp" ? null : split("/", var.ip_config)[0]
}
