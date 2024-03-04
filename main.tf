terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
  backend "azurerm" {
      resource_group_name  = "tfstate"
      storage_account_name = "tfstate909"
      container_name       = "tfstate"
      key                  = "terraform.tfstate"
  }

}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "tf-test" {
  name     = "tf-test"
  location = var.location
}

resource "azurerm_virtual_network" "tf-vnet" {
  name                = "tf-vnet"
  location            = azurerm_resource_group.tf-test.location
  resource_group_name = azurerm_resource_group.tf-test.name
  address_space       = ["10.4.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  count = var.vm_count
  name                 = "subnet-${count.index}"
  resource_group_name  = azurerm_resource_group.tf-test.name
  virtual_network_name = azurerm_virtual_network.tf-vnet.name
  address_prefixes     = ["10.4.${count.index +1}.0/24"]
}


resource "azurerm_network_security_group" "nsg" {
  name                = "tf-secgroup"
  location            = azurerm_resource_group.tf-test.location
  resource_group_name = azurerm_resource_group.tf-test.name
}

resource "azurerm_network_security_rule" "nsg-rule" {
  name                        = "ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf-test.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_subnet_network_security_group_association" "nsg-association" {
  count = var.vm_count
  subnet_id                 = azurerm_subnet.subnet[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "pip" {
  count = var.vm_count
  name                = "tf-publicip-${count.index}"
  resource_group_name = azurerm_resource_group.tf-test.name
  location            = azurerm_resource_group.tf-test.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  count = var.vm_count
  name                = "tf-nic-${count.index}"
  location            = azurerm_resource_group.tf-test.location
  resource_group_name = azurerm_resource_group.tf-test.name

  ip_configuration {
    name                          = "basic"
    subnet_id                     = azurerm_subnet.subnet[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[count.index].id
  }
}

resource "azurerm_virtual_machine" "vm" {
  count = var.vm_count
  name                  = "tf-vm-${count.index}"
  location              = azurerm_resource_group.tf-test.location
  resource_group_name   = azurerm_resource_group.tf-test.name
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  vm_size               = var.vm_size

  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "tf-osdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "testpc"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}