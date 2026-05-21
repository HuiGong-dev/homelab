variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the Proxmox template to clone from"
  type        = number
}

variable "full_clone" {
  description = "Whether to create a full clone from the template"
  type        = bool
  default     = true
}

variable "vm_id" {
  description = "VM ID to assign to the new VM"
  type        = number
}

variable "description" {
  description = "VM description"
  type        = string
  default     = "Managed by OpenTofu"
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 32
}

variable "datastore_id" {
  description = "Proxmox datastore ID for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ip_config" {
  description = "Cloud-init IPv4 address, for example dhcp or 192.168.178.20/24"
  type        = string
  default     = "dhcp"
}

variable "ipv4_gateway" {
  description = "Optional Cloud-init IPv4 gateway"
  type        = string
  default     = null
}

variable "ci_user" {
  description = "Cloud-init user"
  type        = string
  default     = "hui"
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init user"
  type        = string
}

variable "tags" {
  description = "VM tags"
  type        = list(string)
  default     = ["opentofu", "homelab"]
}

variable "started" {
  description = "Whether the VM should be started after creation"
  type        = bool
  default     = true
}

variable "stop_on_destroy" {
  description = "Whether to stop the VM before destroying it"
  type        = bool
  default     = true
}
