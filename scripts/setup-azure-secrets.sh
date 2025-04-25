#!/bin/bash

# Standard header for scripts
# Description: Script to create Azure-related secrets in GitHub repository

REPO_MAIN="MicroTodoSuite/microservice-app-ops"
REPOS_MICROSERVICES=(
  "MicroTodoSuite/microservice-app-users-api"
  "MicroTodoSuite/microservice-app-todos-api"
  "MicroTodoSuite/microservice-app-auth-api"
  "MicroTodoSuite/microservice-app-log-message-processor"
  "MicroTodoSuite/microservice-app-prometheus"
  "MicroTodoSuite/microservice-app-frontend"
)

echo "🛠️ Configurando secrets para la infraestructura Azure..."

# ==============================================
# Configuración en el repositorio principal (ops)
# ==============================================
echo "🔧 Configurando secrets en $REPO_MAIN..."

# Terraform State Secrets
gh secret set TF_STATE_BASE_INFRASTRUCTURE_KEY -b "base-infrastructure.tfstate" --repo $REPO_MAIN && echo "✓ TF_STATE_BASE_INFRASTRUCTURE_KEY"
gh secret set TF_STATE_CONTAINER_APPS_KEY -b "container-apps.tfstate" --repo $REPO_MAIN && echo "✓ TF_STATE_CONTAINER_APPS_KEY"

# Azure Configuration
gh secret set AZURE_LOCATION -b "eastus" --repo $REPO_MAIN && echo "✓ AZURE_LOCATION"
gh secret set AZURE_RESOURCE_GROUP_NAME -b "microservice-app-rg-gaco" --repo $REPO_MAIN && echo "✓ AZURE_RESOURCE_GROUP_NAME"

# Container Registry
gh secret set ACR_NAME -b "msappacrgaco" --repo $REPO_MAIN && echo "✓ ACR_NAME"
gh secret set ACR_SKU -b "Basic" --repo $REPO_MAIN && echo "✓ ACR_SKU"
gh secret set ACR_ADMIN_ENABLED -b "true" --repo $REPO_MAIN && echo "✓ ACR_ADMIN_ENABLED"

# Container Apps
gh secret set CONTAINER_APPS_ENVIRONMENT_NAME -b "ms-env-gaco" --repo $REPO_MAIN && echo "✓ CONTAINER_APPS_ENVIRONMENT_NAME"

# App Secrets
gh secret set JWT_SECRET -b "PRFT" --repo $REPO_MAIN && echo "✓ JWT_SECRET"

# Tags
gh secret set STANDARD_TAGS -b '{"Environment":"Prod","Project":"Microservice App","Owner":"DevOps Team","Creator":"terraform"}' --repo $REPO_MAIN && echo "✓ STANDARD_TAGS"

# ==============================================
# Configuración en repositorios de microservicios
# ==============================================
echo "🔧 Configurando variables en repositorios de microservicios..."

for REPO in "${REPOS_MICROSERVICES[@]}"; do
  echo "📦 Procesando $REPO..."
  
  # Configurar AZURE_RESOURCE_GROUP_NAME (mismo valor que en el repo principal)
  gh secret set AZURE_RESOURCE_GROUP_NAME -b "microservice-app-rg-gaco" --repo $REPO && echo "✓ AZURE_RESOURCE_GROUP_NAME"
  
  # Configurar ACR_NAME (mismo valor que en el repo principal)
  gh secret set ACR_NAME -b "msappacrgaco" --repo $REPO && echo "✓ ACR_NAME"
  
  echo "   ✅ $REPO configurado"
  echo "   ──────────────────────────"
done

echo "✅ Todos los secrets se han configurado correctamente"