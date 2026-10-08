# Same backend identity as the original infra Azure root. These names are not
# credentials. This copy is inactive until one control repository is selected.
# Never create a second state or migrate/copy the existing state for this copy.
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
