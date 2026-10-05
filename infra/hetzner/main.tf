terraform {
  required_version = ">= 1.10.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
  }
  # Partial configuration is supplied by the operator at init. Never silently
  # fall back to local state for this root.
  backend "s3" {}
}

provider "hcloud" {} # HCLOUD_TOKEN comes from the operator environment.

variable "name" {
  type    = string
  default = "forge"
}
variable "location" {
  type        = string
  description = "Hetzner location compatible with the chosen network zone."
}
variable "network_zone" {
  type    = string
  default = "eu-central"
}
variable "operator_cidrs" {
  type = list(string)
  validation {
    condition = length(var.operator_cidrs) > 0 && alltrue([
      for cidr in var.operator_cidrs : can(cidrhost(cidr, 0)) && try(tonumber(split("/", cidr)[1]), 0) > 0
    ])
    error_message = "Supply explicit operator networks; world-open SSH is not permitted."
  }
}
variable "hosts" {
  type = object({
    app    = object({ image = string, server_type = string })
    runner = object({ image = string, server_type = string })
  })
  description = "Reviewed NixOS snapshot IDs and server types; images must satisfy each host bootstrap contract."
}

resource "hcloud_network" "forge" {
  name     = var.name
  ip_range = "10.42.0.0/16"
  lifecycle { prevent_destroy = true }
}
resource "hcloud_network_subnet" "forge" {
  network_id   = hcloud_network.forge.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = "10.42.1.0/24"
  lifecycle { prevent_destroy = true }
}
resource "hcloud_firewall" "forge" {
  for_each = var.hosts
  name     = "${var.name}-${each.key}"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.operator_cidrs
  }
  dynamic "rule" {
    for_each = each.key == "app" ? toset(["80", "443", "2222"]) : toset([])
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }
}
resource "hcloud_server" "forge" {
  for_each                 = var.hosts
  name                     = "${var.name}-${each.key}"
  image                    = each.value.image
  server_type              = each.value.server_type
  location                 = var.location
  firewall_ids             = [hcloud_firewall.forge[each.key].id]
  delete_protection        = each.key == "app"
  rebuild_protection       = each.key == "app"
  shutdown_before_deletion = true
  network {
    network_id = hcloud_network.forge.id
    ip         = each.key == "app" ? "10.42.1.10" : "10.42.1.20"
  }
  depends_on = [hcloud_network_subnet.forge]
  # Even runner replacement requires an explicit reviewed lifecycle change.
  lifecycle { prevent_destroy = true }
}
output "hosts" {
  value = { for role, host in hcloud_server.forge : role => {
    id = host.id, ipv4 = host.ipv4_address, ipv6 = host.ipv6_address
  } }
}
