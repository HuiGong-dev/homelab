resource "proxmox_virtual_environment_vm" "test_vm_01" {
  name        = "test-vm-01"
  description = "Managed by OpenTofu"
  tags        = ["opentofu", "ansible", "test"]

  node_name = var.node_name
  vm_id     = 110

  clone {
    vm_id = 9001
    full  = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "192.168.178.60/24"
        gateway = "192.168.178.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  started = true

  stop_on_destroy = true
}