data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "k3s" {
  name     = "rg-${local.name_prefix}-mw"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "k3s" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "k3s" {
  name                 = "snet-k3s"
  resource_group_name  = azurerm_resource_group.k3s.name
  virtual_network_name = azurerm_virtual_network.k3s.name
  address_prefixes     = ["10.60.1.0/24"]

  # Cost-first exception for this student portfolio environment. This opts in
  # to Azure default outbound access so the private VM can install k3s and pull
  # images without a billable public IP or NAT Gateway. Do not copy this choice
  # to a production environment.
  default_outbound_access_enabled = true
}

resource "azurerm_network_security_group" "k3s" {
  name                = "nsg-${local.name_prefix}"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name
  tags                = local.common_tags

  # No inbound Internet rule is intentionally defined. Initial administration
  # uses Azure Run Command; application ingress will use Cloudflare Tunnel.
}

resource "azurerm_network_interface" "k3s" {
  name                = "nic-${local.name_prefix}"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "primary"
    primary                       = true
    subnet_id                     = azurerm_subnet.k3s.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.1.10"
  }
}

resource "azurerm_network_interface_security_group_association" "k3s" {
  network_interface_id      = azurerm_network_interface.k3s.id
  network_security_group_id = azurerm_network_security_group.k3s.id
}

resource "azurerm_linux_virtual_machine" "k3s" {
  name                = "vm-${local.name_prefix}"
  computer_name       = "getlink-k3s"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name
  size                = var.vm_size
  priority            = "Regular"
  admin_username      = var.admin_username

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  provision_vm_agent              = true
  allow_extension_operations      = true

  network_interface_ids = [azurerm_network_interface.k3s.id]

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    k3s_version = var.k3s_version
  }))

  os_disk {
    name                 = "osdisk-${local.name_prefix}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}

  lifecycle {
    precondition {
      condition     = var.location == "malaysiawest"
      error_message = "VM deployment outside Malaysia West is prohibited."
    }

    precondition {
      condition     = var.vm_size == "Standard_B2as_v2"
      error_message = "VM SKU must remain Standard_B2as_v2."
    }
  }

  depends_on = [
    azurerm_network_interface_security_group_association.k3s
  ]

  tags = local.common_tags
}

resource "azurerm_network_security_group" "sonarqube" {
  name                = "nsg-${local.name_prefix}-sonarqube"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name

  # No inbound rule is intentional. SonarQube is published only through a
  # separately managed, outbound-only Cloudflare Tunnel connector.

  tags = merge(local.common_tags, {
    Component = "SonarQube"
  })
}

resource "azurerm_network_interface" "sonarqube" {
  name                = "nic-${local.name_prefix}-sonarqube"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name

  ip_configuration {
    name                          = "primary"
    primary                       = true
    subnet_id                     = azurerm_subnet.k3s.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.sonarqube_private_ip_address
  }

  tags = merge(local.common_tags, {
    Component = "SonarQube"
  })
}

resource "azurerm_network_interface_security_group_association" "sonarqube" {
  network_interface_id      = azurerm_network_interface.sonarqube.id
  network_security_group_id = azurerm_network_security_group.sonarqube.id
}

resource "azurerm_linux_virtual_machine" "sonarqube" {
  name                = "vm-${local.name_prefix}-sonarqube"
  computer_name       = "getlink-sonarqube"
  location            = azurerm_resource_group.k3s.location
  resource_group_name = azurerm_resource_group.k3s.name
  size                = var.sonarqube_vm_size
  priority            = "Regular"
  admin_username      = var.admin_username

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  provision_vm_agent              = true
  allow_extension_operations      = true

  network_interface_ids = [azurerm_network_interface.sonarqube.id]

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  custom_data = base64encode(file("${path.module}/sonarqube-cloud-init.yaml"))

  os_disk {
    name                 = "osdisk-${local.name_prefix}-sonarqube"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}

  lifecycle {
    precondition {
      condition     = var.location == "malaysiawest"
      error_message = "SonarQube deployment outside Malaysia West is prohibited."
    }

    precondition {
      condition     = var.sonarqube_vm_size == "Standard_B2as_v2"
      error_message = "SonarQube VM SKU must remain Standard_B2as_v2."
    }
  }

  depends_on = [
    azurerm_network_interface_security_group_association.sonarqube,
  ]

  tags = merge(local.common_tags, {
    Component = "SonarQube"
  })
}

resource "azurerm_role_definition" "vm_self_deallocate" {
  name        = "${local.name_prefix}-vm-self-deallocate"
  scope       = data.azurerm_subscription.current.id
  description = "Allows only reading and deallocating the getlink portfolio VM."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/deallocate/action",
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id,
  ]
}

resource "azurerm_role_assignment" "vm_self_deallocate" {
  scope              = azurerm_linux_virtual_machine.k3s.id
  role_definition_id = azurerm_role_definition.vm_self_deallocate.role_definition_resource_id
  principal_id       = azurerm_linux_virtual_machine.k3s.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "sonarqube_self_deallocate" {
  scope              = azurerm_linux_virtual_machine.sonarqube.id
  role_definition_id = azurerm_role_definition.vm_self_deallocate.role_definition_resource_id
  principal_id       = azurerm_linux_virtual_machine.sonarqube.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_virtual_machine_extension" "self_deallocate_guard" {
  name                 = "self-deallocate-guard"
  virtual_machine_id   = azurerm_linux_virtual_machine.k3s.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "bash -c 'echo ${base64encode(file("${path.module}/scripts/configure-self-deallocate.sh"))} | base64 --decode | bash'"
  })

  depends_on = [
    azurerm_role_assignment.vm_self_deallocate,
  ]
}

resource "azurerm_virtual_machine_extension" "sonarqube_bootstrap" {
  name                 = "sonarqube-bootstrap"
  virtual_machine_id   = azurerm_linux_virtual_machine.sonarqube.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "bash -c 'set -euo pipefail; bootstrap=/tmp/bootstrap-sonarqube.sh; trap \"rm -f $${bootstrap}\" EXIT; echo ${base64encode(file("${path.module}/scripts/configure-self-deallocate.sh"))} | base64 --decode | bash; echo ${base64encode(file("${path.module}/scripts/bootstrap-sonarqube.sh"))} | base64 --decode > $${bootstrap}; chmod 0700 $${bootstrap}; env SONARQUBE_IMAGE=${var.sonarqube_image} POSTGRES_IMAGE=${var.sonarqube_postgres_image} CLOUDFLARED_IMAGE=${var.sonarqube_cloudflared_image} $${bootstrap}'"
  })

  depends_on = [
    azurerm_role_assignment.sonarqube_self_deallocate,
  ]

  tags = merge(local.common_tags, {
    Component = "SonarQube"
  })
}
