output "resource_group_name" {
  description = "Resource group containing the k3s VM."
  value       = azurerm_resource_group.k3s.name
}

output "vm_name" {
  description = "Name of the single-node k3s VM."
  value       = azurerm_linux_virtual_machine.k3s.name
}

output "private_ip_address" {
  description = "Private IP address of the k3s VM."
  value       = azurerm_network_interface.k3s.private_ip_address
}

output "verify_k3s_command" {
  description = "Azure CLI command that checks k3s without opening inbound SSH."
  value       = "az vm run-command invoke --resource-group ${azurerm_resource_group.k3s.name} --name ${azurerm_linux_virtual_machine.k3s.name} --command-id RunShellScript --scripts 'sudo k3s kubectl get nodes -o wide' --output table"
}

output "deallocate_command" {
  description = "Run after each demo session to stop VM compute billing."
  value       = "az vm deallocate --resource-group ${azurerm_resource_group.k3s.name} --name ${azurerm_linux_virtual_machine.k3s.name}"
}

output "start_command" {
  description = "Start the VM before a demo session."
  value       = "az vm start --resource-group ${azurerm_resource_group.k3s.name} --name ${azurerm_linux_virtual_machine.k3s.name}"
}

output "verify_self_deallocate_guard_command" {
  description = "Azure CLI command that displays the VM's self-deallocation timer."
  value       = "az vm run-command invoke --resource-group ${azurerm_resource_group.k3s.name} --name ${azurerm_linux_virtual_machine.k3s.name} --command-id RunShellScript --scripts 'sudo systemctl list-timers azure-self-deallocate.timer --all --no-pager' --query 'value[0].message' --output tsv"
}

output "sonarqube_vm_name" {
  description = "Name of the isolated SonarQube Community Build VM."
  value       = azurerm_linux_virtual_machine.sonarqube.name
}

output "sonarqube_private_ip_address" {
  description = "Private IP address of the SonarQube VM."
  value       = azurerm_network_interface.sonarqube.private_ip_address
}

output "sonarqube_url" {
  description = "Expected public URL after the separately managed Cloudflare Tunnel route is configured."
  value       = "https://${var.sonarqube_hostname}"
}

output "sonarqube_start_command" {
  description = "Start the SonarQube VM before a work session. The repository helper also waits for application health."
  value       = "./scripts/sonarqube-start.ps1"
}

output "sonarqube_deallocate_command" {
  description = "Deallocate the SonarQube VM after a work session to stop compute billing."
  value       = "./scripts/sonarqube-stop.ps1"
}

output "sonarqube_status_command" {
  description = "Show Azure power state and, when running, Docker Compose and endpoint health."
  value       = "./scripts/sonarqube-status.ps1"
}

output "configure_sonarqube_tunnel_script" {
  description = "Script to pass as a Managed Run Command with TUNNEL_TOKEN supplied only as a protected parameter."
  value       = "${path.module}/scripts/configure-sonarqube-cloudflare-token.sh"
}
