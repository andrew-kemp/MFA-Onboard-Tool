// ──────────────────────────────────────────────────────────────────
// MFA Onboard Tool – Azure Infrastructure (Bicep)
// Deploys: Storage Account, App Insights, Function App (with MI),
//          and API Connections for the Logic App.
// Usage:
//   az deployment group create -g <rg-name> -f infra/main.bicep \
//     -p functionAppName=<name> storageAccountName=<name>
// ──────────────────────────────────────────────────────────────────

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the storage account (lowercase, 3-24 chars)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Name of the Function App')
param functionAppName string

@description('Name of the Application Insights workspace')
param appInsightsName string = 'appi-${functionAppName}'

@description('SharePoint site URL for function app settings')
param sharePointSiteUrl string = ''

@description('SharePoint list ID for function app settings')
param sharePointListId string = ''

@description('MFA security group ID')
param mfaGroupId string = ''

// ── Storage Account ──────────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// ── Application Insights ─────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
  }
}

// ── App Service Plan (Consumption) ───────────────────────────────
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${functionAppName}'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

// ── Function App ─────────────────────────────────────────────────
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'SHAREPOINT_SITE_URL'
          value: sharePointSiteUrl
        }
        {
          name: 'SHAREPOINT_LIST_ID'
          value: sharePointListId
        }
        {
          name: 'MFA_GROUP_ID'
          value: mfaGroupId
        }
      ]
    }
  }
}

// ── Office 365 API Connection ────────────────────────────────────
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-mfa'
  location: location
  properties: {
    displayName: 'MFA Onboarding Office 365'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

// ── SharePoint API Connection ────────────────────────────────────
resource sharepointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'sharepointonline-mfa'
  location: location
  properties: {
    displayName: 'MFA Onboarding SharePoint'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────────
@description('Function App Managed Identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Application Insights instrumentation key')
output appInsightsKey string = appInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Office 365 connection resource ID')
output office365ConnectionId string = office365Connection.id

@description('SharePoint connection resource ID')
output sharepointConnectionId string = sharepointConnection.id
