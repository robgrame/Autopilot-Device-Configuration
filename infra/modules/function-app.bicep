param name string
param location string = resourceGroup().location
param tags object = {}
param applicationInsightsName string
param appServicePlanId string
param storageAccountName string
param deploymentStorageContainerName string
param appSettings object = {}
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 10

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

var baseAppSettings = {
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__blobServiceUri: storageAccount.properties.primaryEndpoints.blob
  AzureWebJobsStorage__queueServiceUri: storageAccount.properties.primaryEndpoints.queue
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'
  APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
}

module functionApp 'br/public:avm/res/web/site:0.15.1' = {
  name: 'autopilot-flex-consumption'
  params: {
    kind: 'functionapp,linux'
    name: name
    location: location
    tags: union(tags, {
      'azd-service-name': 'worker'
    })
    serverFarmResourceId: appServicePlanId
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: []
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: 'powershell'
        version: '7.4'
      }
    }
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    appSettingsKeyValuePairs: union(appSettings, baseAppSettings)
  }
}

output name string = functionApp.outputs.name
output principalId string = functionApp.outputs.?systemAssignedMIPrincipalId ?? ''
