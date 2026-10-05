terraform {
  required_version = ">= 1.10.0"
  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "3.33.1"
    }
  }
  # This one-time bootstrap deliberately uses local state. Preserve an
  # encrypted recovery copy independently of the buckets it creates.
  backend "local" {}
}

provider "minio" {
  minio_server        = var.s3_endpoint
  minio_region        = var.s3_region
  minio_ssl           = true
  skip_bucket_tagging = true
  # Credentials come from MINIO_USER / MINIO_PASSWORD, never input variables.
}

variable "s3_endpoint" {
  type        = string
  description = "TLS S3 endpoint hostname, without a URL scheme."
}
variable "s3_region" {
  type = string
}
variable "buckets" {
  type = object({ state = string, backups = string })
  validation {
    condition     = var.buckets.state != var.buckets.backups
    error_message = "Infrastructure state and service backups require separate buckets."
  }
}

resource "minio_s3_bucket" "forge" {
  for_each       = var.buckets
  bucket         = each.value
  acl            = "private"
  force_destroy  = false
  object_locking = false
  lifecycle { prevent_destroy = true }
}

resource "minio_s3_bucket_versioning" "forge" {
  for_each = minio_s3_bucket.forge
  bucket   = each.value.id
  versioning_configuration { status = "Enabled" }
  lifecycle { prevent_destroy = true }
}

output "buckets" {
  value = { for role, bucket in minio_s3_bucket.forge : role => bucket.id }
}
