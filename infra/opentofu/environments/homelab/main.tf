locals {
  test_vm_01_ip_config = "192.168.178.60/24"
}

module "test_vm_01" {
  source = "../../modules/proxmox-vm"

  vm_name        = "test-vm-01"
  description    = "Managed by OpenTofu"
  tags           = ["opentofu", "ansible", "test"]
  node_name      = var.proxmox_node_name
  vm_id          = 110
  template_vm_id = var.template_vm_id
  full_clone     = true

  cpu_cores    = 2
  memory_mb    = 2048
  datastore_id = "local-lvm"
  bridge       = "vmbr0"
  disk_size_gb = 20

  ip_config    = local.test_vm_01_ip_config
  ipv4_gateway = "192.168.178.1"

  ci_user         = "ansible"
  ssh_public_keys = [var.ssh_public_key_automation]
  started         = true
  stop_on_destroy = true
}
