terraform {
  backend "azurerm" {
    resource_group_name  = "rg-getlink-tfstate"
    storage_account_name = "stgetlinktf498374"
    container_name       = "tfstate"
    key                  = "azure-k3s.tfstate"
    use_azuread_auth     = true
    use_cli              = true
  }
}
