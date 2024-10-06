# Install prerequisites
Register-AzResourceProvider -ProviderNamespace Microsoft.Migrate
Install-Module -Name Az.ResourceMover -Force
$subscriptionId = "d8c01b16-9767-42f6-86ad-51ac2ad7071f"
$metadataRG = "MoveCollectionMatadataRG"
# Create the resource group for metadata
New-AzResourceGroup -Name $metadataRG -Location "East US 2"
# Creating a new move collection and granting it access over the subscription
New-AzResourceMoverMoveCollection -Name "MoveCollection01" -ResourceGroupName $metadataRG -SubscriptionId $subscriptionId -SourceRegion "eastus" -TargetRegion "westus" -Location  "East US 2" -IdentityType SystemAssigned
$moveCollection = Get-AzResourceMoverMoveCollection -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -Name "MoveCollection01"
$identityPrincipalId = $moveCollection.IdentityPrincipalId
New-AzRoleAssignment -ObjectId $identityPrincipalId -RoleDefinitionName Contributor -Scope "/subscriptions/$subscriptionId"
New-AzRoleAssignment -ObjectId $identityPrincipalId -RoleDefinitionName "User Access Administrator" -Scope "/subscriptions/$subscriptionId"
# Add resources to the move collection
$resourcesToMove = Get-AzResource -ResourceGroupName "ResourcesTobeMoved"
$resourcesToMove | foreach {
    $resID = $psitem.ResourceID
    $resName = $psitem.Name
    $resType = $psitem.ResourceType
    Add-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -SourceId $resID -Name $resName -ResourceSettingResourceType $resType -ResourceSettingTargetResourceName $resName
}
$rgID = (Get-AzResourceGroup -Name ResourcesTobeMoved).ResourceID
Add-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -SourceId $rgID -Name ResourcesTobeMoved -ResourceSettingResourceType "resourcegroups" -ResourceSettingTargetResourceName ResourcesTobeMoved-westUS
# Resolve dependencies
Resolve-AzResourceMoverMoveCollectionDependency -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01"
# Prepare the resources
$resourcesInTheCollection = Get-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" | select name, MoveStatusMoveState, ProvisioningState, MoveStatusMessage
Invoke-AzResourceMoverPrepare -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource "ResourcesTobeMoved"
Do {
    $resourcesInTheCollection | where { $PSITem.name -ne "ResourcesTobeMoved" } | foreach {
        Invoke-AzResourceMoverPrepare -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource $PSItem.name
    }
}until((Get-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" | select MoveStatusMoveState).MoveStatusMoveState -notcontains "PreparePending")
# Initiate The Move
Invoke-AzResourceMoverInitiateMove -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource "ResourcesTobeMoved"
Do {
    $resourcesInTheCollection | where { $PSITem.name -ne "ResourcesTobeMoved" } | foreach {
        Invoke-AzResourceMoverInitiateMove -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource $PSItem.name
    }
}until((Get-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" | select MoveStatusMoveState).MoveStatusMoveState -notcontains "MovePending")
# Commit The Move
Invoke-AzResourceMoverCommit -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource "ResourcesTobeMoved"
Do {
    $resourcesInTheCollection | where { $PSITem.name -ne "ResourcesTobeMoved" } | foreach {
        Invoke-AzResourceMoverCommit -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" -MoveResource $PSItem.name
    }
}until((Get-AzResourceMoverMoveResource -SubscriptionId $subscriptionId -ResourceGroupName $metadataRG -MoveCollectionName "MoveCollection01" | select MoveStatusMoveState).MoveStatusMoveState -notcontains "CommitPending")