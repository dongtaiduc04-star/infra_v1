variable "location" {
  description = "Azure region allowed by the Azure for Students subscription policy."
  type        = string
  default     = "malaysiawest"

  validation {
    condition     = var.location == "malaysiawest"
    error_message = "This cost-controlled stack is restricted to Malaysia West."
  }
}

variable "project_name" {
  description = "Project name used in Azure resource names and tags."
  type        = string
  default     = "getlink-dtd"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "portfolio"
}

variable "vm_size" {
  description = "Azure VM SKU for the single-node k3s server."
  type        = string
  default     = "Standard_B2as_v2"

  validation {
    condition     = var.vm_size == "Standard_B2as_v2"
    error_message = "Only Standard_B2as_v2 is allowed by this cost-controlled stack."
  }
}

variable "sonarqube_vm_size" {
  description = "Azure VM SKU for the isolated SonarQube Community Build host. Two vCPUs and 8 GiB are the cost-controlled minimum for SonarQube plus PostgreSQL in this portfolio environment."
  type        = string
  default     = "Standard_B2as_v2"

  validation {
    condition     = var.sonarqube_vm_size == "Standard_B2as_v2"
    error_message = "Only Standard_B2as_v2 is allowed for the cost-controlled SonarQube VM."
  }
}

variable "sonarqube_private_ip_address" {
  description = "Static private address assigned to the SonarQube VM in the existing k3s subnet."
  type        = string
  default     = "10.60.1.20"

  validation {
    condition     = can(cidrhost("10.60.1.0/24", 20)) && var.sonarqube_private_ip_address == cidrhost("10.60.1.0/24", 20)
    error_message = "The cost-controlled topology reserves 10.60.1.20 for SonarQube."
  }
}

variable "sonarqube_hostname" {
  description = "Public hostname that will be routed through the separately managed Cloudflare Tunnel. Terraform does not create this DNS record or store the tunnel token."
  type        = string
  default     = "sonar-azure.dongtaiduc.me"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", var.sonarqube_hostname))
    error_message = "sonarqube_hostname must be a lowercase fully-qualified DNS hostname."
  }
}

variable "sonarqube_image" {
  description = "Pinned official SonarQube Community Build image."
  type        = string
  default     = "sonarqube:26.9.0.129388-community"

  validation {
    condition     = can(regex("^sonarqube:[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+-community$", var.sonarqube_image))
    error_message = "sonarqube_image must use an exact official Community Build tag, never latest/community."
  }
}

variable "sonarqube_postgres_image" {
  description = "Pinned official PostgreSQL image used by SonarQube."
  type        = string
  default     = "postgres:18.6-bookworm"

  validation {
    condition     = can(regex("^postgres:18\\.[0-9]+-bookworm$", var.sonarqube_postgres_image))
    error_message = "sonarqube_postgres_image must pin a supported PostgreSQL 18 bookworm patch tag."
  }
}

variable "sonarqube_cloudflared_image" {
  description = "Pinned Cloudflare Tunnel image for the SonarQube-only tunnel replica."
  type        = string
  default     = "cloudflare/cloudflared:2026.9.3"

  validation {
    condition     = can(regex("^cloudflare/cloudflared:[0-9]{4}\\.[0-9]+\\.[0-9]+$", var.sonarqube_cloudflared_image))
    error_message = "sonarqube_cloudflared_image must use an exact calendar-version tag."
  }
}

variable "admin_username" {
  description = "Linux administrator username. Password login remains disabled."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Local path to the SSH public key installed on the VM."
  type        = string
  default     = "~/.ssh/azure_k3s_ed25519.pub"

  validation {
    condition     = fileexists(pathexpand(var.ssh_public_key_path))
    error_message = "The SSH public key does not exist. Create ~/.ssh/azure_k3s_ed25519.pub first."
  }
}

variable "k3s_version" {
  description = "Exact stable k3s version installed by cloud-init."
  type        = string
  default     = "v1.36.4+k3s1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be an exact stable release such as v1.36.4+k3s1."
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostControl = "AzureStudents"
  }
}
