function Test-CcProp($obj, [string] $name) {
    # Works for both a parsed JSON object and a hashtable.
    if ($obj -is [System.Collections.IDictionary]) { return $obj.Contains($name) }
    return [bool]($obj.PSObject.Properties.Name -contains $name)
}

function Get-CcSetting($entry, $registry, [string] $name) {
    if ((Test-CcProp $entry $name) -and $entry.$name) { return $entry.$name }
    if ((Test-CcProp $registry $name) -and $registry.$name) { return $registry.$name }
    return $null
}
