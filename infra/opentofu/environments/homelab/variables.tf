variable "proxmox_endpoint" {
  type      = string
  sensitive = true
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}

variable "node_name" {
  type    = string
  default = "pve"
}