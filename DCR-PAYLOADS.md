# Data Collection Rule (DCR) - Payload de Exemplo

## O que é DCR (Data Collection Rule)?

A **Data Collection Rule (DCR)** define como coletar dados de diferentes fontes (VMs, aplicações) e transformá-los antes de enviar ao Log Analytics.

---

## 📋 Payload 1: DCR Básica para Eventos Windows

Para coletar eventos do Windows de uma VM e enviar para Log Analytics:

```json
{
  "location": "East US",
  "properties": {
    "streamDeclarations": {
      "Custom-MyLogData": {
        "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "Computer",
            "type": "string"
          },
          {
            "name": "EventID",
            "type": "int"
          },
          {
            "name": "EventLevel",
            "type": "string"
          },
          {
            "name": "Message",
            "type": "string"
          }
        ]
      }
    },
    "dataSources": {
      "windowsEventLogs": [
        {
          "name": "eventLogsDataSource",
          "streams": [
            "Microsoft-Event"
          ],
          "xPathQueries": [
            "System!*[System[(Level=2 or Level=3)]]"
          ],
          "samplingFrequencyInSeconds": 0,
          "logNames": [
            "System",
            "Application"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "centralWorkspace",
          "workspaceResourceId": "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/seu-resource-group/providers/microsoft.operationalinsights/workspaces/seu-workspace"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": [
          "Microsoft-Event"
        ],
        "destinations": [
          "centralWorkspace"
        ],
        "transformKql": "source\n| project TimeGenerated, Computer, EventID=tostring(EventID), EventLevel=LevelDisplayName, Message"
      }
    ]
  }
}
```

---

## 📋 Payload 2: DCR para Logs Customizados (Aplicação)

Para sua Function App enviar logs customizados:

```json
{
  "location": "East US",
  "properties": {
    "streamDeclarations": {
      "Custom-AcessoAppsLog": {
        "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "LogLevel",
            "type": "string"
          },
          {
            "name": "FunctionName",
            "type": "string"
          },
          {
            "name": "Message",
            "type": "string"
          },
          {
            "name": "UserId",
            "type": "string"
          },
          {
            "name": "AppName",
            "type": "string"
          },
          {
            "name": "Duration",
            "type": "real"
          }
        ]
      }
    },
    "dataSources": {
      "logs": [
        {
          "name": "customLogDataSource",
          "streams": [
            "Custom-AcessoAppsLog"
          ],
          "samplingFrequencyInSeconds": 0
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
          "Custom-AcessoAppsLog"
        ],
        "destinations": [
          "logAnalyticsWorkspace"
        ]
      }
    ]
  }
}
```

---

## 📋 Payload 3: DCR para Métricas de Performance

Para coletar dados de performance de VMs:

```json
{
  "location": "East US",
  "properties": {
    "streamDeclarations": {
      "Microsoft-Perf": {
        "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "Computer",
            "type": "string"
          },
          {
            "name": "ObjectName",
            "type": "string"
          },
          {
            "name": "CounterName",
            "type": "string"
          },
          {
            "name": "CounterValue",
            "type": "real"
          }
        ]
      }
    },
    "dataSources": {
      "performanceCounters": [
        {
          "name": "perfCountersDataSource",
          "streams": [
            "Microsoft-Perf"
          ],
          "samplingFrequencyInSeconds": 60,
          "counterSpecifiers": [
            "\\Processor(_Total)\\% Processor Time",
            "\\Memory\\Available MBytes",
            "\\LogicalDisk(C:)\\% Disk Time",
            "\\Network Interface(*)\\Bytes Sent/sec"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "workspace",
          "workspaceResourceId": "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/seu-resource-group/providers/microsoft.operationalinsights/workspaces/seu-workspace"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": [
          "Microsoft-Perf"
        ],
        "destinations": [
          "workspace"
        ]
      }
    ]
  }
}
```

---

## 📋 Payload 4: DCR Completa com Transformação (KQL)

Para transformar dados antes de salvar (mais avançado):

```json
{
  "location": "East US",
  "properties": {
    "streamDeclarations": {
      "Custom-WebLogs": {
        "columns": [
          {
            "name": "TimeGenerated",
            "type": "datetime"
          },
          {
            "name": "RequestId",
            "type": "string"
          },
          {
            "name": "StatusCode",
            "type": "int"
          },
          {
            "name": "ResponseTime",
            "type": "real"
          },
          {
            "name": "UserAgent",
            "type": "string"
          },
          {
            "name": "Endpoint",
            "type": "string"
          }
        ]
      }
    },
    "dataSources": {
      "logs": [
        {
          "name": "webLogsSource",
          "streams": [
            "Custom-WebLogs"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "myWorkspace",
          "workspaceResourceId": "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/seu-resource-group/providers/microsoft.operationalinsights/workspaces/seu-workspace"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": [
          "Custom-WebLogs"
        ],
        "destinations": [
          "myWorkspace"
        ],
        "transformKql": "source\n| where StatusCode >= 400\n| project TimeGenerated, RequestId, StatusCode, ResponseTime=todouble(ResponseTime), UserAgent, Endpoint\n| extend IsError = (StatusCode >= 500), IsWarning = (StatusCode >= 400 and StatusCode < 500)"
      }
    ]
  }
}
```

---

## 🚀 Como Criar a DCR via CLI

### Opção 1: Usando arquivo JSON

```powershell
# 1. Salvar um dos payloads acima em um arquivo (exemplo: dcr-config.json)

# 2. Criar a DCR
$resourceGroup = "seu-resource-group"
$dcrName = "minha-dcr"
$location = "East US"

az monitor data-collection rule create `
  --resource-group $resourceGroup `
  --name $dcrName `
  --location $location `
  --rule-file "dcr-config.json"

# 3. Verificar criação
az monitor data-collection rule list `
  --resource-group $resourceGroup `
  --output table
```

### Opção 2: Criar com az CLI (Payload inline)

```powershell
$payload = @{
    location = "East US"
    properties = @{
        streamDeclarations = @{
            "Custom-MyLog" = @{
                columns = @(
                    @{ name = "TimeGenerated"; type = "datetime" },
                    @{ name = "Message"; type = "string" }
                )
            }
        }
        dataSources = @{
            logs = @(
                @{
                    name = "customLogs"
                    streams = @("Custom-MyLog")
                }
            )
        }
        destinations = @{
            logAnalytics = @(
                @{
                    name = "workspace"
                    workspaceResourceId = "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/seu-resource-group/providers/microsoft.operationalinsights/workspaces/seu-workspace"
                }
            )
        }
        dataFlows = @(
            @{
                streams = @("Custom-MyLog")
                destinations = @("workspace")
            }
        )
    }
}

$resourceGroup = "seu-resource-group"
$dcrName = "minha-dcr"

az monitor data-collection rule create `
  --resource-group $resourceGroup `
  --name $dcrName `
  --rule ($payload | ConvertTo-Json -Depth 10)
```

---

## 📊 Listar e Gerenciar DCRs

```powershell
# Listar todas as DCRs de um grupo
az monitor data-collection rule list `
  --resource-group $resourceGroup `
  --output table

# Mostrar detalhes de uma DCR
az monitor data-collection rule show `
  --resource-group $resourceGroup `
  --name $dcrName `
  --output jsonc

# Atualizar uma DCR
az monitor data-collection rule update `
  --resource-group $resourceGroup `
  --name $dcrName `
  --rule-file "dcr-config-updated.json"

# Deletar uma DCR
az monitor data-collection rule delete `
  --resource-group $resourceGroup `
  --name $dcrName
```

---

## 🔗 Associar DCR a VMs

```powershell
# Listar regras de associação
az monitor data-collection rule association list `
  --resource-group $resourceGroup

# Criar associação entre DCR e VM
$vmResourceId = "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachines/sua-vm"
$dcrResourceId = "/subscriptions/SEU-SUBSCRIPTION-ID/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName"

az monitor data-collection rule association create `
  --rule-id $dcrResourceId `
  --target-resource-id $vmResourceId `
  --description "Associação DCR para sua VM"
```

---

## 💡 Template para sua Function App

Para sua **SumarizacaoAcessoApps**, use este payload customizado:

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
          },
          {
            "name": "FunctionName",
            "type": "string"
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

---

## 📚 Referências

- [DCR Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Data Collection Rule Schema](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-schema)
- [KQL Transformations](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-kql)
