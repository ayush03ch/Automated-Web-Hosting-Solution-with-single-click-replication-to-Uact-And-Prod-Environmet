output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "lb_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}
