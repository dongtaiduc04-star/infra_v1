# Supply your own backend.hcl only for a separately authorized deployment.
# Do not connect this publication to the original operational state.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
    use_cli          = true
  }
}
