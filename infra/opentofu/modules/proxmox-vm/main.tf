resource "proxmox_virtual_environment_vm" "this" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = var.tags
  started     = var.started

  stop_on_destroy = var.stop_on_destroy

  clone {
    vm_id = var.template_vm_id
    full  = var.full_clone
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
  }

  network_device {
    bridge = var.bridge
  }

  operating_system {
    type = "l26"
  }

  vga {
    type = "std"
  }

  initialization {
    datastore_id = var.datastore_id

    user_account {
      username = var.ci_user
      keys     = var.ssh_public_keys
      password = var.ci_user_password
    }

    ip_config {
      ipv4 {
        address = var.ip_config
        gateway = var.ipv4_gateway
      }
    }
  }
}
