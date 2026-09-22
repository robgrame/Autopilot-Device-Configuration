targetScope = 'subscription'

@minLength(1)
@maxLength(32)
@description('AZD environment name used to generate resource names.')
param environmentName string

@description('Azure region for all resources.')
@allowed([
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'northeurope'
  'norwayeast'
  'spaincentral'
  'swedencentral'
  'uksouth'
  'ukwest'
  'westeurope'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string = 'westeurope'

param resourceGroupName string = ''
param functionAppName string = ''
param storageAccountName string = ''
param applicationInsightsName string = ''
param logAnalyticsName string = ''
param appServicePlanName string = ''
param timerSchedule string = '0 0 */6 * * *'
param dryRun bool = true
param pilotSerialNumbers string = ''
param deviceNameValidationPattern string = '^[A-Za-z][A-Za-z0-9-]{0,14}$'
param groupTagValidationPattern string = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
param tags object = {}

var resourceToken = take(toLower(uniqueString(subscription().id, environmentName, location)), 8)
var commonTags = union(tags, {
  'azd-env-name': environmentName
  application: 'autopilot-device-configuration'
  environment: environmentName
  managedBy: 'bicep'
})
var resolvedFunctionAppName = !empty(functionAppName) ? functionAppName : 'func-autopilot-${resourceToken}'
var resolvedStorageAccountName = !empty(storageAccountName) ? storageAccountName : 'stautopilot${resourceToken}'
var deploymentStorageContainerName = 'app-package'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : 'rg-autopilot-${environmentName}'
  location: location
  tags: commonTags
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'function-plan'
  scope: resourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : 'plan-autopilot-${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: commonTags
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'function-storage'
  scope: resourceGroup
  params: {
    name: resolvedStorageAccountName
    location: location
    tags: commonTags
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [
        {
          name: deploymentStorageContainerName
        }
      ]
    }
    minimumTlsVersion: 'TLS1_2'
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: 'log-analytics'
  scope: resourceGroup
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : 'log-autopilot-${resourceToken}'
    location: location
    tags: commonTags
    dataRetention: 30
  }
}

module applicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'application-insights'
  scope: resourceGroup
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : 'appi-autopilot-${resourceToken}'
    location: location
    tags: commonTags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

module functionApp './modules/function-app.bicep' = {
  name: 'function-app'
  scope: resourceGroup
  params: {
    name: resolvedFunctionAppName
    location: location
    tags: commonTags
    applicationInsightsName: applicationInsights.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    appSettings: {
      TIMER_SCHEDULE: timerSchedule
      DRY_RUN: string(dryRun)
      INVENTORY_PROVIDER: 'package-json'
      INVENTORY_PATH: 'inventory/sample-inventory.json'
      DEVICE_NAME_VALIDATION_PATTERN: deviceNameValidationPattern
      GROUP_TAG_VALIDATION_PATTERN: groupTagValidationPattern
      PILOT_SERIAL_NUMBERS: pilotSerialNumbers
      LOG_LEVEL: 'Information'
      GRAPH_API_VERSION: 'v1.0'
      MAX_RETRY_COUNT: '4'
      RETRY_BASE_DELAY_SECONDS: '2'
      GRAPH_REQUEST_TIMEOUT_SECONDS: '100'
    }
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  scope: resourceGroup
  params: {
    storageAccountName: storage.outputs.name
    applicationInsightsName: applicationInsights.outputs.name
    managedIdentityPrincipalId: functionApp.outputs.principalId
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_FUNCTION_NAME string = functionApp.outputs.name
output AZURE_FUNCTION_PRINCIPAL_ID string = functionApp.outputs.principalId
output APPLICATIONINSIGHTS_NAME string = applicationInsights.outputs.name
