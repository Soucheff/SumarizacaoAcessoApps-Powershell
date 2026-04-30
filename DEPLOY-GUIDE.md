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

### Passo 8: Criar Data Collection Rule (DCR)

A **DCR** define como coletar e estruturar os dados que sua Function App enviará para o Log Analytics.

#### 8.1 Criar arquivo de configuração DCR

Salve este JSON como `dcr-config.json`:

```json
{
  "location": "East US",
  "properties": {
    "streamDeclarations": {
      "Custom-AcessoApsLog": {
        "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "ExecutionId",
            "type": "string"
          ---

          ## 📤 Enviar Dados para a DCR

          Após criar a DCR, sua Function App pode enviar dados usando a API HTTP de ingestão. Aqui está um exemplo para usar no seu código PowerShell:

          ```powershell
          # Função para enviar logs para DCR
          function Send-LogsToDCR {
            param(
              [string]$ExecutionId,
              [string]$FunctionName,
              [string]$LogLevel,
              [string]$Message,
              [string]$AppName,
              [int]$AccessCount,
              [decimal]$ExecutionTime,
              [string]$Status
            )
    
            # Obter token via Managed Identity
            $token = (Invoke-RestMethod `
              -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2017-12-01&resource=https://monitor.azure.com" `
              -Headers @{"Metadata"="true"}).access_token
    
            # Preparar o payload
            $logEntry = @{
              TimeGenerated = (Get-Date -Format "o")
              ExecutionId = $ExecutionId
              FunctionName = $FunctionName
              LogLevel = $LogLevel
              Message = $Message
              AppName = $AppName
              AccessCount = $AccessCount
              ExecutionTime = $ExecutionTime
              Status = $Status
            }
    
            # Headers
            $headers = @{
              "Authorization" = "Bearer $token"
              "Content-Type" = "application/json"
            }
    
            # Endpoint da DCR (você precisa obter isso do seu recurso)
            $dcrEndpoint = "https://seu-workspace.eastus-1.ingest.monitor.azure.com/dataCollectionRules/dcr-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/streams/Custom-AcessoApsLog?api-version=2023-01-01"
    
            try {
              Invoke-RestMethod `
                -Uri $dcrEndpoint `
                -Method Post `
                -Headers $headers `
                -Body ($logEntry | ConvertTo-Json)
        
              Write-Output "✅ Log enviado com sucesso"
            }
            catch {
              Write-Error "❌ Erro ao enviar log: $_"
            }
          }

          # Usar a função dentro da sua Azure Function
          Send-LogsToDCR `
            -ExecutionId "exec-12345" `
            -FunctionName "Diario" `
            -LogLevel "Info" `
            -Message "Resumo diário processado" `
            -AppName "SumarizacaoAcessoApps" `
            -AccessCount 150 `
            -ExecutionTime 2.5 `
            -Status "Success"
          ```

          ### Obter Endpoint da DCR

          ```powershell
          # O endpoint está disponível em:
          $resourceGroup = "seu-resource-group"
          $dcrName = "SumarizacaoAcessoApps-DCR"

          # Listar todas as ingestões de endpoint
          az monitor data-collection rule show `
            --resource-group $resourceGroup `
            --name $dcrName `
            --query "properties.dataCollectionEndpoints" -o jsonc
          ```

          ---

          ## 📖 Documentos Adicionais

          - **[DCR-PAYLOADS.md](DCR-PAYLOADS.md)** - Exemplos completos de payloads DCR para diferentes cenários
            - Eventos Windows
            - Logs Customizados
            - Métricas de Performance
            - Transformação com KQL

          ---

          ## 📚 Referências
          },
          {
            "name": "LogLevel",
            "type": "string"
          },
          {
            "name": "Message",
            "type": "string"
          },
          {
            "name": "AppName",
            "type": "string"
          },
          {
            "name": "AccessCount",
            "type": "int"
          },
          {
            "name": "ExecutionTime",
            "type": "real"
          },
          {
            "name": "Status",
            "type": "string"
          }
        ]
      }
    },
    "dataSources": {
      "logs": [
        {
          "name": "acessoAppsLogSource",
          "streams": [
            "Custom-AcessoApsLog"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "logAnalyticsWorkspace",
          "workspaceResourceId": "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/seu-resource-group/providers/microsoft.operationalinsights/workspaces/seu-workspace"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": [
          "Custom-AcessoApsLog"
        ],
        "destinations": [
          "logAnalyticsWorkspace"
        ],
        "transformKql": "source\n| project TimeGenerated, ExecutionId, FunctionName, LogLevel, Message, AppName, AccessCount=toint(AccessCount), ExecutionTime=todouble(ExecutionTime), Status\n| extend IsError = (LogLevel == \"Error\"), IsCritical = (LogLevel == \"Critical\")"
      }
    ]
  }
}
```

#### 8.2 Criar a DCR no Azure

```powershell
$dcrName = "SumarizacaoAcessoApps-DCR"
$workspaceId = (az monitor log-analytics workspace list `
  --resource-group $resourceGroup `
  --query "[0].id" -o tsv)

# Substituir variáveis no arquivo JSON
$dcrConfig = Get-Content "dcr-config.json" | ConvertFrom-Json
$dcrConfig.properties.destinations.logAnalytics[0].workspaceResourceId = $workspaceId
$dcrConfig | ConvertTo-Json -Depth 10 | Set-Content "dcr-config-ready.json"

# Criar a DCR
az monitor data-collection rule create `
  --resource-group $resourceGroup `
  --name $dcrName `
  --location $location `
  --rule-file "dcr-config-ready.json"

# Obter o Resource ID da DCR
$dcrResourceId = az monitor data-collection rule show `
  --resource-group $resourceGroup `
  --name $dcrName `
  --query id -o tsv

Write-Host "✅ DCR criada: $dcrResourceId"
```

#### 8.3 Obter Endpoint HTTP da DCR

```powershell
# Listar regras de ingestão (endpoint para enviar dados)
az monitor data-collection rule association list `
  --resource-group $resourceGroup `
  --output table

# A URL para enviar dados será algo como:
# https://seu-workspace.eastus-1.ingest.monitor.azure.com/dataCollectionRules/dcr-id/streams/Custom-AcessoApsLog?api-version=2023-01-01
```

### Passo 9: Deploy do Código


```powershell
# Navegar para a pasta do projeto
cd c:\dev\FuncApp\SumarizacaoAcessoApps-Powershell

# Deploy usando Azure Functions Core Tools
func azure functionapp publish $functionAppName

# Ou com build remoto (recomendado para primeira vez)
func azure functionapp publish $functionAppName --build remote
```

### Passo 10: Verificar Deploy
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

# 8. CRIAR DATA COLLECTION RULE (DCR)
$dcrName = "SumarizacaoAcessoApps-DCR"
$dcrPayload = @{
  location = $location
  properties = @{
    streamDeclarations = @{
      "Custom-AcessoApsLog" = @{
        columns = @(
          @{ name = "TimeGenerated"; type = "datetime" },
          @{ name = "ExecutionId"; type = "string" },
          @{ name = "FunctionName"; type = "string" },
          @{ name = "LogLevel"; type = "string" },
          @{ name = "Message"; type = "string" },
          @{ name = "AppName"; type = "string" },
          @{ name = "AccessCount"; type = "int" },
          @{ name = "ExecutionTime"; type = "real" },
          @{ name = "Status"; type = "string" }
        )
      }
    }
    dataSources = @{
      logs = @(
        @{
          name = "acessoAppsLogSource"
          streams = @("Custom-AcessoApsLog")
        }
      )
    }
    destinations = @{
      logAnalytics = @(
        @{
          name = "logAnalyticsWorkspace"
          workspaceResourceId = (az monitor log-analytics workspace list `
            --resource-group $resourceGroup `
            --query "[0].id" -o tsv)
        }
      )
    }
    dataFlows = @(
      @{
        streams = @("Custom-AcessoApsLog")
        destinations = @("logAnalyticsWorkspace")
      }
    )
  }
}

$dcrPayload | ConvertTo-Json -Depth 10 | Set-Content "dcr-config.json"

az monitor data-collection rule create `
  --resource-group $resourceGroup `
  --name $dcrName `
  --location $location `
  --rule-file "dcr-config.json"

Write-Host "✅ DCR criada: $dcrName"

# 9. FAZER DEPLOY
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
