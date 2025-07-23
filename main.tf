provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "main" {
  name     = "rg-${var.env_name}"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.env_name}"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "subnet-${var.env_name}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.env_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "lb" {
  name                = "lb-pip-${var.env_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "main" {
  name                = "lb-${var.env_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}


# Create NICs for each VM
resource "azurerm_network_interface" "vm_nic" {
  count               = var.vm_count
  name                = "nic-${var.env_name}-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    load_balancer_backend_address_pools_ids = [
      azurerm_lb_backend_address_pool.bepool.id
    ]
  }
}

# Linux Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = "vm-${var.env_name}-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  size                = var.vm_size
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm_nic[count.index].id]

  admin_password = "Password1234!"  #change for prod

  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Install Apache via cloud-init
  custom_data = filebase64("cloud-init.txt")
}

# LB Backend Pool
resource "azurerm_lb_backend_address_pool" "bepool" {
  name                = "backend-pool"
  loadbalancer_id     = azurerm_lb.main.id
  resource_group_name = azurerm_resource_group.main.name
}

# LB Health Probe
resource "azurerm_lb_probe" "http_probe" {
  name                = "http-probe"
  resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# LB Rule to forward HTTP traffic
resource "azurerm_lb_rule" "http_rule" {
  name                           = "http-rule"
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.bepool.id
  probe_id                       = azurerm_lb_probe.http_probe.id
}
