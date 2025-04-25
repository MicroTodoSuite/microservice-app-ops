#!/bin/bash

# Standard header for scripts
# Description: Script to create Azure-related secrets in GitHub repository

REPO="MicroTodoSuite/microservice-app-ops"

echo "🛠️ Configurando secrets para la infraestructura Azure..."

# Terraform State Secrets
gh secret set TF_STATE_BASE_INFRASTRUCTURE_KEY -b "base-infrastructure.tfstate" --repo $REPO && echo "✓ TF_STATE_BASE_INFRASTRUCTURE_KEY"
gh secret set TF_STATE_CONTAINER_APPS_KEY -b "container-apps.tfstate" --repo $REPO && echo "✓ TF_STATE_CONTAINER_APPS_KEY"

# Azure Configuration
gh secret set AZURE_LOCATION -b "eastus" --repo $REPO && echo "✓ AZURE_LOCATION"
gh secret set AZURE_RESOURCE_GROUP_NAME -b "microservice-app-rg-gaco" --repo $REPO && echo "✓ AZURE_RESOURCE_GROUP_NAME"

# Container Registry
gh secret set ACR_NAME -b "msappacrgaco" --repo $REPO && echo "✓ ACR_NAME"
gh secret set ACR_SKU -b "Basic" --repo $REPO && echo "✓ ACR_SKU"
gh secret set ACR_ADMIN_ENABLED -b "true" --repo $REPO && echo "✓ ACR_ADMIN_ENABLED"

# Container Apps
gh secret set CONTAINER_APPS_ENVIRONMENT_NAME -b "ms-env-gaco" --repo $REPO && echo "✓ CONTAINER_APPS_ENVIRONMENT_NAME"

# App Secrets
gh secret set JWT_SECRET -b "PRFT" --repo $REPO && echo "✓ JWT_SECRET"

# Tags
gh secret set STANDARD_TAGS -b '{"Environment":"Prod","Project":"Microservice App","Owner":"DevOps Team","Creator":"terraform"}' --repo $REPO && echo "✓ STANDARD_TAGS"

echo "✅ Todos los secrets se han configurado correctamente en $REPO"
