locals {
  adguard_ip_config       = "192.168.178.12/24"
  k3s_server_01_ip_config = "192.168.178.13/24"
  k3s_agent_01_ip_config  = "192.168.178.14/24"
  router_ip               = "192.168.178.1"
  dns_servers             = [split("/", local.adguard_ip_config)[0], local.router_ip]
}

module "adguard" {
  source = "../../modules/proxmox-vm"

  vm_name        = "adguard"
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

  ip_config    = local.adguard_ip_config
  ipv4_gateway = "192.168.178.1"

  ci_user          = "ansible"
  ci_user_password = var.ci_user_password
  ssh_public_keys  = [var.ssh_public_key_automation]
  started          = true
  stop_on_destroy  = true
}

module "k3s-server-01" {
  source = "../../modules/proxmox-vm"

  vm_name        = "k3s-server-01"
  description    = "Managed by OpenTofu"
  tags           = ["opentofu", "ansible", "k3s", "k3s-server"]
  node_name      = var.proxmox_node_name
  vm_id          = 104
  template_vm_id = var.template_vm_id
  full_clone     = true

  cpu_cores    = 4
  memory_mb    = 12288
  datastore_id = "local-lvm"
  bridge       = "vmbr0"
  disk_size_gb = 250

  ip_config    = local.k3s_server_01_ip_config
  ipv4_gateway = local.router_ip
  dns_servers  = local.dns_servers

  ci_user          = "ansible"
  ci_user_password = var.ci_user_password
  ssh_public_keys  = [var.ssh_public_key_automation]
  started          = true
  stop_on_destroy  = true
}

module "k3s-agent-01" {
  source = "../../modules/proxmox-vm"

  vm_name        = "k3s-agent-01"
  description    = "Managed by OpenTofu"
  tags           = ["opentofu", "ansible", "k3s", "k3s-agent"]
  node_name      = var.proxmox_node_name
  vm_id          = 105
  template_vm_id = var.template_vm_id
  full_clone     = true

  cpu_cores    = 2
  memory_mb    = 4096
  datastore_id = "local-lvm"
  bridge       = "vmbr0"
  disk_size_gb = 50

  ip_config    = local.k3s_agent_01_ip_config
  ipv4_gateway = local.router_ip
  dns_servers  = local.dns_servers

  ci_user          = "ansible"
  ci_user_password = var.ci_user_password
  ssh_public_keys  = [var.ssh_public_key_automation]
  started          = true
  stop_on_destroy  = true
}

moved {
  from = module.adguard_vm_01
  to   = module.adguard
}
