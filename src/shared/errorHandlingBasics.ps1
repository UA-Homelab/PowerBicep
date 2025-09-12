function Test-LocationName {
    param (
        [string]$Location
    )

    $locationShortcutList = Get-Content -Path "../lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    if ($null -eq $locationShortcutList.$Location) {
        throw "Location '$Location' is not recognized. Please use a valid Azure region name."
    }

    return $true
}

function Test-ApplicationNameShort {
    param (
        [string]$ApplicationNameShort
    )

    if ($ApplicationNameShort -notmatch '^[a-zA-Z]{2,10}$') {
        throw "The value '$ApplicationNameShort' for -ApplicationNameShort is invalid. It must be 2-10 characters long and contain only letters."
    }

    return $true
}