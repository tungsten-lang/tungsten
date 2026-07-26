# Dual-architecture Tungsten dev AMI (arm64 Graviton + x86_64 Intel/AMD).
#
# AMIs are architecture-specific — an image is a snapshot of compiled binaries
# for ONE CPU arch, so Graviton and Intel each need their own AMI. This single
# template builds BOTH from one shared provisioner (provision.sh): `packer build`
# emits `tungsten-dev-arm64-<ts>` and `tungsten-dev-x86_64-<ts>`.
#
# Usage:
#   cd scripts/packer-tungsten-dev
#   packer init .
#   packer build .                        # both arches
#   packer build -only='*.arm64' .        # just Graviton
#   packer build -var region=us-west-2 .
#
# Uses spot instances for the builders (cheap). Packer creates a temporary key
# pair + security group automatically; it only needs a public subnet, which the
# subnet_filter below auto-selects (this account has no default VPC).

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region"            { default = "us-east-1" }
variable "arm_instance_type" { default = "c7g.large" }   # Graviton3
variable "x86_instance_type" { default = "c7i.large" }   # Intel Sapphire Rapids
variable "volume_gb"         { default = 20 }

locals { ts = formatdate("YYYYMMDD-hhmmss", timestamp()) }

# ---- Graviton (arm64) ----
source "amazon-ebs" "arm64" {
  region        = var.region
  instance_type = var.arm_instance_type
  ssh_username  = "ec2-user"
  ami_name      = "tungsten-dev-arm64-${local.ts}"
  ami_description = "Tungsten dev toolchain + ML stack (arm64/Graviton)"

  source_ami_filter {
    filters     = { name = "al2023-ami-2023*-arm64", architecture = "arm64", root-device-type = "ebs", virtualization-type = "hvm" }
    owners      = ["amazon"]
    most_recent = true
  }

  # cheap spot builder
  spot_price          = "auto"
  spot_instance_types = [var.arm_instance_type]

  associate_public_ip_address = true
  subnet_filter {
    filters   = { "map-public-ip-on-launch" : "true" }
    most_free = true
    random    = false
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }
  tags = { Project = "tungsten", Role = "dev", Arch = "arm64" }
}

# ---- Intel/AMD (x86_64) ----
source "amazon-ebs" "x86_64" {
  region        = var.region
  instance_type = var.x86_instance_type
  ssh_username  = "ec2-user"
  ami_name      = "tungsten-dev-x86_64-${local.ts}"
  ami_description = "Tungsten dev toolchain + ML stack (x86_64)"

  source_ami_filter {
    filters     = { name = "al2023-ami-2023*-x86_64", architecture = "x86_64", root-device-type = "ebs", virtualization-type = "hvm" }
    owners      = ["amazon"]
    most_recent = true
  }

  spot_price          = "auto"
  spot_instance_types = [var.x86_instance_type]

  associate_public_ip_address = true
  subnet_filter {
    filters   = { "map-public-ip-on-launch" : "true" }
    most_free = true
    random    = false
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }
  tags = { Project = "tungsten", Role = "dev", Arch = "x86_64" }
}

build {
  name    = "tungsten-dev"
  sources = ["source.amazon-ebs.arm64", "source.amazon-ebs.x86_64"]

  # One provisioner, both arches — dnf/pip/gem resolve arch-native packages,
  # SAT solvers build from source, so the same script produces correct images.
  provisioner "shell" {
    script          = "provision.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  post-processor "manifest" {
    output = "manifest.json"   # records the two AMI IDs produced
  }
}
