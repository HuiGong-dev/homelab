variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "template_vm_id" {
  description = "Default template VM ID"
  type        = number
}

variable "ci_user_password" {
  description = "Default cloud-init user password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "ssh_public_key_automation" {
  description = "SSH public key for automation"
  type        = string
}