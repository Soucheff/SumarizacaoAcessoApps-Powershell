# Authenticate with the managed identity / DefaultAzureCredential equivalent.
# When running in Azure Functions with managed identity enabled, MSI_SECRET is set.
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null
}
