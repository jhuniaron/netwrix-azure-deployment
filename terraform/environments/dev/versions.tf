terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend values are injected at `terraform init` via -backend-config flags
  # so no sensitive values live in source control.
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # Don't wipe Key Vault on destroy — protects against accidental data loss
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      # Prevent destroying a resource group that still has resources in it
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id = var.subscription_id
}
