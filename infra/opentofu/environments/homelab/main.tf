locals {
  adguard_vm_01_ip_config = "192.168.178.13/24"
}

module "adguard_vm_01" {
  source = "../../modules/proxmox-vm"

  vm_name        = "adguard-02"
  description    = "Managed by OpenTofu"
  tags           = ["opentofu", "ansible", "adguard"]
  node_name      = var.proxmox_node_name
  vm_id          = 103
  template_vm_id = var.template_vm_id
  full_clone     = true

  cpu_cores    = 1
  memory_mb    = 1024
  datastore_id = "local-lvm"
  bridge       = "vmbr0"
  disk_size_gb = 10

  ip_config    = local.adguard_vm_01_ip_config
  ipv4_gateway = "192.168.178.1"

  ci_user         = "ansible"
  ssh_public_keys = [var.ssh_public_key_automation]
  started         = true
  stop_on_destroy = true
}
