function New-RandomNumber {
    param (
        [string]$ResourceNameShort,
        [string]$SubscriptionId,
        [string]$ApplicationNameShort,
        [string]$Environment,
        [string]$LocationShort
    )
    $inputString = $SubscriptionId + "$ApplicationNameShort$Environment$LocationShort"
    $hash = [System.BitConverter]::ToInt32((New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($inputString)), 0)
    $intValue = [math]::Abs($hash)
    Get-Random -Minimum 1000 -Maximum 9999 -SetSeed $intValue
}

function New-PBResourceGroupName {
    param (
        [string]$ApplicationNameShort,
        [string]$Environment,
        [string]$Location,
        [string]$Index = "001",
        [switch]$NetworkResourceGroup,
        [int]$NamingConventionOption = 1
    )

    $ResourceType = "Microsoft.Resources/resourceGroups"

    $resourceNameShortcuts = Get-Content -Path "../lib/resourceNameShortcuts.json" | ConvertFrom-Json -AsHashtable

    $resourceNameShort = $resourceNameShortcuts.$ResourceType

    $locationShortcutList = Get-Content -Path "../lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    $locationShort = $locationShortcutList.$Location

    if ($NetworkResourceGroup) {
        $resourceName = "$resourceNameShort-network-$ApplicationNameShort-$Environment-$locationShort-$Index"
    } else {
        $resourceName = "$resourceNameShort-$ApplicationNameShort-$Environment-$locationShort-$Index"
    }

    return $resourceName
}

function New-PBResourceName {
    param (
        [string]$ResourceType,
        [string]$ApplicationNameShort,
        [string]$Environment,
        [string]$Location,
        [string]$Index = "001",
        [int]$NamingConventionOption = 1
    )

    $subscriptionId = (Get-AzContext).Subscription.Id

    $resourceNameShortcuts = Get-Content -Path "../lib/resourceNameShortcuts.json" | ConvertFrom-Json -AsHashtable

    $resourceNameShort = $resourceNameShortcuts.$ResourceType

    $locationShortcutList = Get-Content -Path "../lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    $locationShort = $locationShortcutList.$Location

    if ($resourceNameShort -eq "st") {
        $randomNumber = Get-RandomNumber -SubscriptionId $subscriptionId -ApplicationNameShort $ApplicationNameShort -Environment $Environment -LocationShort $locationShort -ResourceNameShort $resourceNameShort
        switch ($NamingConventionOption) {
            1 { $resourceName = "$resourceNameShort$ApplicationNameShort$Environment$locationShort$randomNumber" }
            2 { $resourceName = "$ApplicationNameShort$Environment$LocationShort$ResourceNameShort$randomNumber" }
            default { $resourceName = "$resourceNameShort$ApplicationNameShort$Environment$LocationShort$randomNumber" }
        }
    } else {
        switch ($NamingConventionOption) {
            1 { $resourceName = "$resourceNameShort-$ApplicationNameShort-$Environment-$locationShort-$Index" }
            2 { $resourceName = "$ApplicationNameShort-$Environment-$LocationShort-$ResourceNameShort" }
            default { $resourceName = "$ResourceNameShort-$ApplicationNameShort-$Environment-$LocationShort-$Index" }
        }
    }

    return $resourceName
}