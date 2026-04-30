# Guia de Deploy - SumarizacaoAcessoApps Function App

## 📋 Pré-requisitos

### 1. Ferramentas Necessárias
```powershell
# Instalar Azure CLI
winget install Microsoft.AzureCLI

# Instalar Azure Functions Core Tools
winget install Microsoft.Azure.FunctionsCoreTools

# Verificar instalação
az --version
func --version
```

### 2. Conta Azure
- Uma subscription ativa no Azure
- Permissões para criar recursos (Contributor ou equivalente)
- Estar logado: `az login`

### 3. Verificar conectividade
```powershell
# Verificar se está logado
az account show

# Listar subscriptions
az account list --output table
```

---

## 🚀 Passo a Passo de Deploy

### Passo 1: Configurar Variáveis de Ambiente

```powershell
# Define as variáveis (customize conforme necessário)
$resourceGroup = "seu-resource-group"
$location = "East US"  # ou sua região preferida
$functionAppName = "SumarizacaoAcessoApps"
$storageAccountName = "suastorageaccount"  # Nome único (letras minúsculas e números)
$logAnalyticsWorkspaceId = "seu-workspace-id"
$logAnalyticsKey = "sua-chave-primaria"
```

### Passo 2: Verificar/Criar Resource Group

```powershell
# Verificar se existe
$rg = az group exists --name $resourceGroup
if ($rg -eq "false") {
    Write-Host "Criando Resource Group: $resourceGroup"
    az group create --name $resourceGroup --location $location
} else {
    Write-Host "Resource Group já existe: $resourceGroup"
}
```

### Passo 3: Verificar/Criar Storage Account

```powershell
# Listar Storage Accounts existentes
az storage account list --resource-group $resourceGroup --output table

# Se não existir, criar nova:
az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard_LRS

# Se já existe, apenas usar o nome
Write-Host "Storage Account a usar: $storageAccountName"
```

### Passo 4: Criar Function App

```powershell
az functionapp create `
  --resource-group $resourceGroup `
  --consumption-plan-location $location `
  --runtime powershell `
  --runtime-version 7.2 `
  --functions-version 4 `
  --name $functionAppName `
  --storage-account $storageAccountName `
  --os-type Windows
```

### Passo 5: Criar Managed Identity

```powershell
# Ativar Managed Identity (System-assigned)
az functionapp identity assign `
  --resource-group $resourceGroup `
  --name $functionAppName `
  --identities "[system]"

# Obter o ID da Managed Identity
$principalId = az functionapp identity show `
  --resource-group $resourceGroup `
  --name $functionAppName `
  --query principalId -o tsv

Write-Host "Managed Identity criada com ID: $principalId"
```

### Passo 6: Configurar Permissões da Managed Identity

#### 6.1 Permissão para Log Analytics (Leitura)

```powershell
# Obter Resource ID do Log Analytics Workspace
$workspaceResourceId = "/subscriptions/SEU-SUBSCRIPTION-ID/resourcegroups/$resourceGroup/providers/microsoft.operationalinsights/workspaces/SEU-WORKSPACE-NAME"

# Atribuir role "Log Analytics Reader" (role id: 73c42c96-874c-492b-b04d-ab87d138a893)
az role assignment create `
  --assignee-object-id $principalId `
  --role "Log Analytics Reader" `
  --scope $workspaceResourceId

# Ou, se precisar de permissão de escrita:
# az role assignment create `
#   --assignee-object-id $principalId `
#   --role "Contributor" `
#   --scope $workspaceResourceId
```

#### 6.2 Permissão para Storage Account (Leitura/Escrita)

```powershell
# Obter Resource ID da Storage Account
$storageResourceId = az storage account show `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --query id -o tsv

# Atribuir role "Storage Blob Data Contributor"
az role assignment create `
  --assignee-object-id $principalId `
  --role "Storage Blob Data Contributor" `
  --scope $storageResourceId
```

#### 6.3 Permissões Adicionais (se necessário)

```powershell
# Se precisar ler de Key Vault
az role assignment create `
  --assignee-object-id $principalId `
  --role "Key Vault Secrets User" `
  --scope "/subscriptions/SEU-SUBSCRIPTION-ID/resourcegroups/$resourceGroup/providers/microsoft.keyvault/vaults/seu-keyvault"

# Se precisar de Monitor/Application Insights
az role assignment create `
  --assignee-object-id $principalId `
  --role "Monitoring Contributor" `
  --scope "/subscriptions/SEU-SUBSCRIPTION-ID"
```

### Passo 7: Configurar Application Settings

```powershell
# Adicionar variáveis de configuração
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --settings `
    "LogAnalyticsWorkspaceId=$logAnalyticsWorkspaceId" `
    "LogAnalyticsKey=$logAnalyticsKey" `
    "FUNCTIONS_WORKER_RUNTIME=powershell" `
    "ENABLE_MSIS=true"

# Verificar settings
az functionapp config appsettings list `
  --name $functionAppName `
  --resource-group $resourceGroup
```

### Passo 8: Deploy do Código

```powershell
# Navegar para a pasta do projeto
cd c:\dev\FuncApp\SumarizacaoAcessoApps-Powershell

# Deploy usando Azure Functions Core Tools
func azure functionapp publish $functionAppName

# Ou com build remoto (recomendado para primeira vez)
func azure functionapp publish $functionAppName --build remote
```

### Passo 9: Verificar Deploy

```powershell
# Listar funções deployed
az functionapp function list `
  --resource-group $resourceGroup `
  --name $functionAppName

# Ver logs da função
func azure functionapp logstream $functionAppName

# Ou via portal/CLI
az functionapp show `
  --name $functionAppName `
  --resource-group $resourceGroup
```

---

## 🔐 Guia Completo de Managed Identity e Permissões

### O que é Managed Identity?

A **Managed Identity** é uma identidade segura para sua Function App se autenticar em outros serviços Azure **sem usar credenciais** (sem username/password ou connection strings).

### Tipos de Managed Identity

1. **System-assigned**: Criada e gerenciada automaticamente pelo Azure
   - Ciclo de vida ligado ao recurso
   - Uma identity por recurso

2. **User-assigned**: Criada separadamente e atribuída a recursos
   - Ciclo de vida independente
   - Pode ser reutilizada em múltiplos recursos

### Roles Comuns para Managed Identity

| Role | Permissão | Uso |
|------|-----------|-----|
| `Log Analytics Reader` | Ler dados do Log Analytics | Consultas de logs |
| `Log Analytics Contributor` | Ler + Escrever dados | Enviar logs + consultas |
| `Storage Blob Data Reader` | Ler blobs | Leitura de dados |
| `Storage Blob Data Contributor` | Ler + Escrever blobs | Processamento de dados |
| `Key Vault Secrets User` | Ler secrets | Acessar senhas/chaves |
| `Monitoring Contributor` | Gerir monitores | Métricas e alertas |

### Exemplo: Usar Managed Identity no Código PowerShell

```powershell
# Obter token automaticamente (sem credenciais)
$token = (Invoke-RestMethod `
    -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2017-12-01&resource=https://api.loganalytics.io" `
    -Headers @{"Metadata"="true"}).access_token

# Usar o token para chamar API
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Exemplo: Query ao Log Analytics
$body = @{
    "query" = "AzureDiagnostics | take 10"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "https://api.loganalytics.io/v1/workspaces/$LogAnalyticsWorkspaceId/query" `
    -Headers $headers `
    -Method Post `
    -Body $body
```

---

## ✅ Checklist de Permissões

Antes de executar a função, verifique:

```powershell
# 1. Managed Identity está ativa?
az functionapp identity show `
  --resource-group $resourceGroup `
  --name $functionAppName

# 2. Roles foram atribuídas?
az role assignment list `
  --assignee-object-id $principalId `
  --output table

# 3. Function App pode acessar Log Analytics?
# Teste dentro da função com a query acima

# 4. Variáveis de ambiente foram configuradas?
az functionapp config appsettings list `
  --resource-group $resourceGroup `
  --name $functionAppName
```

---

## 🐛 Troubleshooting

### Erro: "Unauthorized" ao acessar Log Analytics

**Solução:**
```powershell
# Verificar se a role foi atribuída corretamente
az role assignment list --assignee-object-id $principalId --output table

# Se não aparecer, executar novamente:
az role assignment create `
  --assignee-object-id $principalId `
  --role "Log Analytics Reader" `
  --scope $workspaceResourceId
```

### Erro: Storage Account não encontrada

**Solução:**
```powershell
# Listar storage accounts disponíveis
az storage account list --resource-group $resourceGroup --output table

# Criar se não existir
az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard_LRS
```

### Função não está sendo acionada pelo Timer

**Verificar:**
```powershell
# Ver logs da função
func azure functionapp logstream $functionAppName

# Ou no portal: Function App > Monitor > Invocations
```

---

## 📝 Script Completo (Tudo de Uma Vez)

```powershell
# ============================================
# SCRIPT COMPLETO DE DEPLOY
# ============================================

# 1. CONFIGURAR VARIÁVEIS
$resourceGroup = "seu-resource-group"
$location = "East US"
$functionAppName = "SumarizacaoAcessoApps"
$storageAccountName = "sua-storage-account"
$subscriptionId = (az account show --query id -o tsv)

# 2. LOGIN
az login
az account set --subscription $subscriptionId

# 3. CRIAR RESOURCE GROUP
az group create --name $resourceGroup --location $location

# 4. CRIAR STORAGE ACCOUNT
az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard_LRS

# 5. CRIAR FUNCTION APP
az functionapp create `
  --resource-group $resourceGroup `
  --consumption-plan-location $location `
  --runtime powershell `
  --runtime-version 7.2 `
  --functions-version 4 `
  --name $functionAppName `
  --storage-account $storageAccountName

# 6. ATIVAR MANAGED IDENTITY
az functionapp identity assign `
  --resource-group $resourceGroup `
  --name $functionAppName `
  --identities "[system]"

$principalId = az functionapp identity show `
  --resource-group $resourceGroup `
  --name $functionAppName `
  --query principalId -o tsv

# 7. ATRIBUIR ROLES
$storageResourceId = az storage account show `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --query id -o tsv

az role assignment create `
  --assignee-object-id $principalId `
  --role "Storage Blob Data Contributor" `
  --scope $storageResourceId

# 8. FAZER DEPLOY
cd c:\dev\FuncApp\SumarizacaoAcessoApps-Powershell
func azure functionapp publish $functionAppName --build remote

Write-Host "✅ Deploy concluído com sucesso!"
```

---

## 📚 Referências

- [Azure Functions PowerShell](https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell)
- [Managed Identity para App Service](https://docs.microsoft.com/en-us/azure/app-service/overview-managed-identity)
- [Azure RBAC Roles](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
- [Log Analytics API](https://dev.loganalytics.io/documentation/overview)
