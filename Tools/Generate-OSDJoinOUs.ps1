Function Generate-XmlHierarchy {
    Param(
        [Parameter(Mandatory=$True, Position=0)]
        [xml] 
        $ImportedData,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Domain,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $DomainFQDN,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $SearchBase,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateScript({[int]::TryParse($_, [ref] $null)})]
        [string[]]
        $Port,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $JoinIdentity,

        [Parameter(Mandatory=$True, Position=1, ValueFromPipelineByPropertyName=$True)]
        [System.Security.PSCredential[]]
        $Credential,

        [Parameter(Mandatory=$False)]
        [string] 
        $XmlFileName
    )

    Begin {
        # Ensure we have aligned arrays. We'll be pulling one for one and we can't manage to do it if we're off our counts.
        if ($Domain.Count -ne $DomainFQDN.Count -or $Domain.Count -ne $SearchBase.Count -or
            $Domain.Count -ne $Server.Count -or $Domain.Count -ne $Port.Count -or
            $Domain.Count -ne $JoinIdentity.Count -or $Domain.Count -ne $Credential.Count) {
            throw [System.ArgumentException]::New("Array parameters all must contain the same number of elements ($($Domain.Count) in this attempt).")
        }

        if (([array] (Get-Module ActiveDirectory)).Count -eq 0) {
            if (([array] (Get-Module -ListAvailable ActiveDirectory)).Count -gt 0) {
                try {
                    Import-Module ActiveDirectory -ErrorAction Stop
                } catch {
                    throw [System.InvalidOperationException]::New('Could not load the required module ActiveDirectory.')
                }
            } else {
                throw [System.InvalidOperationException]::New('The required module ActiveDirectory is not available.')
            }
        }

        Write-Host "Generating Organizational Unit Map..." -ForegroundColor Green

        $XmlDocument = New-Object System.Xml.XmlDocument
        $XmlDocument.AppendChild($XmlDocument.CreateXmlDeclaration('1.0', 'utf-8', $null)) | Out-Null
        $XmlDocument.AppendChild($XmlDocument.CreateElement("OrganizationalUnitMap")) | Out-Null
    }

    Process {
        foreach ($Index in 0..($Domain.Count-1)) {
            $_Domain = $Domain[$Index]
            $_DomainFQDN = $DomainFQDN[$Index]
            $_SearchBase = $SearchBase[$Index]
            $_Server = $Server[$Index]
            $_Port = $Port[$Index]
            $_JoinIdentity = $JoinIdentity[$Index]
            $_Credential = $Credential[$Index]

            Write-Host "Gathering Organizational Units from AD Domain $_Domain..." -ForegroundColor Green

            $ServerArgs = @{}
            if ($_Server -ne $null) {
                $ServerArgs = @{
                    Server = $_Server
                }
            }

            # $Filter = "DistinguishedName -notin $ExcludedOUs"
            $Filter = '*'
            $RootOUList = Get-ADOrganizationalUnit -SearchBase $_SearchBase -SearchScope OneLevel @ServerArgs -Filter $Filter

            # We need to be in our PS Drive for these Commandlets to work. Go there, then set our location back after we're done.
        
            # Don't need to save this anymore.
            # Try to load the manifest first. No point to continue if we can't track our work.
            # Join-Path $Env:USERPROFILE "Desktop\DVY-SCCM Collection Map.xml"
            # $Manifest = Join-Path $Env:USERPROFILE "Desktop\DVY-SCCM Collection Map.xml"

            $XmlDocument.DocumentElement.AppendChild($XmlDocument.CreateElement("OrganizationalUnit")) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("Name")).AppendChild($XmlDocument.CreateTextNode($_Domain)) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("ADDomainName")).AppendChild($XmlDocument.CreateTextNode($_DomainFQDN)) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("Tooltip")).AppendChild($XmlDocument.CreateTextNode("Join the computer to the $_Domain domain.")) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("DistinguishedName")).AppendChild($XmlDocument.CreateTextNode($_SearchBase)) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("HasAccess")).AppendChild($XmlDocument.CreateTextNode($False.ToString())) | Out-Null
            $XmlDocument.DocumentElement.LastChild.AppendChild($XmlDocument.CreateElement("TextColor")).AppendChild($XmlDocument.CreateTextNode('LightGray')) | Out-Null

            # Don't need to save this anymore.

            New-PSDrive -Name $_Domain -PSProvider ActiveDirectory -Root "" -Server $_Server

            foreach ($OU in $RootOUList) {
                $OUHierarchyXml = Process-OrganizationalUnit -Source $OU -JoinIdentity $_JoinIdentity -Domain $_Domain -Server $_Server -OwnerXml $XmlDocument -SelectedAttributes @('Name', 'DistinguishedName', 'TextColor', 'HasAccess')
                if ($OUHierarchyXml -ne $null) {
                    $XmlDocument.DocumentElement.LastChild.AppendChild($OUHierarchyXml) | Out-Null
                }
            }

            Remove-PSDrive -Name $_Domain
        }
    }

    End {
        if (-not [string]::IsNullOrEmpty($XmlFileName)) {
            $XmlDocument.Save((Join-Path (Resolve-Path (Get-Location -PSProvider FileSystem).Path).ProviderPath $XmlFileName))
        }
    }
}

Function Process-OrganizationalUnit {
    Param(
        [Microsoft.ActiveDirectory.Management.ADOrganizationalUnit] $Source,
        [string] $JoinIdentity,
        [System.Xml.XmlDocument] $OwnerXml,
        [string[]] $SelectedAttributes = @(),
        [string] $Server,
        [string] $Domain
    )

    $ObjectTypeGuid = 'bf967a86-0de6-11d0-a285-00aa003049e2'

    $AclList = (Get-Acl "$($Domain):$Source").Access | where IdentityReference -eq $JoinIdentity

    ## Big Decisions Here. Is this someplace we can join to?
    $HasCriteria = 0
    foreach ($Acl in $AclList) {
        if ($Acl.ActiveDirectoryRights -eq 'CreateChild' -and $Acl.ObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Create New Computer Object
            $HasCriteria++
        } elseif ($Acl.ActiveDirectoryRights -eq 'ExtendedRight' -and $Acl.ObjectType -eq 'ab721a53-1e2f-11d0-9819-00aa0040529b' -and $Acl.InheritedObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Change Password right.
            $HasCriteria++
        } elseif ($Acl.ActiveDirectoryRights -eq 'ExtendedRight' -and $Acl.ObjectType -eq '00299570-246d-11d0-a768-00aa006e0529' -and $Acl.InheritedObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Reset Password right.
            $HasCriteria++
        } elseif ($Acl.ObjectType -eq '72e39547-7b18-11d1-adef-00c04fd8d5cd' -and $Acl.InheritedObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Validated Write to DNS Host Name.
            $HasCriteria++
        } elseif ($Acl.ObjectType -eq 'f3a64788-5306-11d1-a9c5-0000f80367c1' -and $Acl.InheritedObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Validated Write to SPN.
            $HasCriteria++
        } elseif ($Acl.ActiveDirectoryRights -eq 'ReadProperty, WriteProperty' -and $Acl.InheritedObjectType -eq $ObjectTypeGuid -and $Acl.AccessControlType -eq 'Allow') {
            # Read/Write All Properties (Required to Enable/Disable Objects).
            $HasCriteria++
        }
    }

    $HasAccess = $False
    $TextColor = "LightGray"
    if ($HasCriteria -ge 6) {
        $HasAccess = $True
        $TextColor = "Black"
        $OutputArgs = @{ForegroundColor = 'Green'}
        # Write-Host "Can successfully join to this OU." -ForegroundColor Green
    } else {
        $OutputArgs = @{ForegroundColor = 'Yellow'}
        # Write-Host "Can NOT successfully join to this OU." -ForegroundColor Yellow
    }

    $ServerArgs = @{}
    if ($Server -ne $null) {
        $ServerArgs = @{
            Server = $Server
        }
    }

    $ChildItems = Get-ADOrganizationalUnit -SearchBase $Source.DistinguishedName -SearchScope OneLevel -Filter * @ServerArgs

    $SourceXml = $OwnerXml.CreateElement("OrganizationalUnit")

    if ($SelectedAttributes.Count -eq 0) {
        $SelectedAttributes = $Source | Get-Member -Type Properties | Select -Expand Name
    }

    # Record properties we care about. Nice neat process.
    foreach ($Attribute in $SelectedAttributes) {
        $SourceXml.AppendChild($OwnerXml.CreateElement($Attribute)) | Out-Null

        switch ($Attribute) {
            'HasAccess' {
                $SourceXml.LastChild.AppendChild($OwnerXml.CreateTextNode($HasAccess.ToString())) | Out-Null
            }
            'TextColor' {
                $SourceXml.LastChild.AppendChild($OwnerXml.CreateTextNode($TextColor)) | Out-Null
            }
            default {
                if ($Source."$Attribute" -ne $null) {
                    $SourceXml.LastChild.AppendChild($OwnerXml.CreateTextNode($Source."$Attribute".ToString())) | Out-Null
                }
            }
        }
    }

    $ChildItems = $ChildItems | Sort-Object -Property Name

    $WritableChildren = 0
    foreach ($Child in $ChildItems) {
        $ChildXml = Process-OrganizationalUnit -Source $Child -JoinIdentity $JoinIdentity -Domain $Domain -Server $Server -OwnerXml $OwnerXml -SelectedAttributes $SelectedAttributes

        if ($ChildXml -ne $null) {
            $WritableChildren++
            $SourceXml.AppendChild($ChildXml) | Out-Null
        }
    }

    if ($HasAccess -eq $False -and $WritableChildren -eq 0) {
        $OutputArgs = @{ForegroundColor = 'Cyan'}
#        Write-Host "Skipping $($Source.DistinguishedName). No Writable Child OUs and no access detected." -ForegroundColor Cyan
    } else {
        Write-Output $SourceXml
    }

    Write-Host "Processed organizational unit $($Source.DistinguishedName), $((@() + $ChildItems).Count) child items" @OutputArgs
}

Generate-XmlHierarchy -XmlFileName '.\OUStructuralMap.xml'

<#

Process Notes ...

PS AD:\> ($ACL = Get-Acl "AD:\<KnownWorkingOU>").Access | Where IdentityReference -eq '<JoinIdentity>'

RightsGuid                              cn                                      displayname
----------                              --                                      -----------
ab721a53-1e2f-11d0-9819-00aa0040529b    User-Change-Password                    Change Password
00299570-246d-11d0-a768-00aa006e0529    User-Force-Change-Password              Reset Password
ab721a54-1e2f-11d0-9819-00aa0040529b    Send-As                                 Send As
ab721a56-1e2f-11d0-9819-00aa0040529b    Receive-As                              Receive As
4c164200-20c0-11d0-a768-00aa006e0529    User-Account-Restrictions               Account Restrictions
77B5B886-944A-11d1-AEBD-0000F80367C1    Personal-Information                    Personal Information
e48d0154-bcf8-11d1-8702-00c04fb96050    Public-Information                      Public Information
72e39547-7b18-11d1-adef-00c04fd8d5cd    Validated-DNS-Host-Name                 Validated write to DNS host name
f3a64788-5306-11d1-a9c5-0000f80367c1    Validated-SPN                           Validated write to service principal...
72e39547-7b18-11d1-adef-00c04fd8d5cd    DNS-Host-Name-Attributes                DNS Host Name Attributes
68B1D179-0D15-4d4f-AB71-46152E79A7BC    Allowed-To-Authenticate                 Allowed to Authenticate
ffa6f046-ca4b-4feb-b40d-04dfee722543    MS-TS-GatewayAccess                     MS-TS-GatewayAccess
80863791-dbe9-4eb8-837e-7f0ab55d9ac7    Validated-MS-DS-Additional-DNS-Host-... Validated write to MS DS Additional ...



--- Read/Write All Properties for Computers (Enable/Disable Object) ---
ActiveDirectoryRights : ReadProperty, WriteProperty
InheritanceType       : Descendents
ObjectType            : 00000000-0000-0000-0000-000000000000
InheritedObjectType   : bf967a86-0de6-11d0-a285-00aa003049e2
ObjectFlags           : InheritedObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : False
InheritanceFlags      : ContainerInherit
PropagationFlags      : InheritOnly

--- Validated Write to SPN for Computers ---
ActiveDirectoryRights : Self
InheritanceType       : Descendents
ObjectType            : f3a64788-5306-11d1-a9c5-0000f80367c1
InheritedObjectType   : bf967a86-0de6-11d0-a285-00aa003049e2
ObjectFlags           : ObjectAceTypePresent, InheritedObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : False
InheritanceFlags      : ContainerInherit
PropagationFlags      : InheritOnly

--- Validated Write to DNS Host Name for Computers ---
ActiveDirectoryRights : Self
InheritanceType       : Descendents
ObjectType            : 72e39547-7b18-11d1-adef-00c04fd8d5cd
InheritedObjectType   : bf967a86-0de6-11d0-a285-00aa003049e2
ObjectFlags           : ObjectAceTypePresent, InheritedObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : False
InheritanceFlags      : ContainerInherit
PropagationFlags      : InheritOnly

--- Reset Password for Computers ---
ActiveDirectoryRights : ExtendedRight
InheritanceType       : Descendents
ObjectType            : 00299570-246d-11d0-a768-00aa006e0529
InheritedObjectType   : bf967a86-0de6-11d0-a285-00aa003049e2
ObjectFlags           : ObjectAceTypePresent, InheritedObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : False
InheritanceFlags      : ContainerInherit
PropagationFlags      : InheritOnly

--- Change Password for Computers ---
ActiveDirectoryRights : ExtendedRight
InheritanceType       : Descendents
ObjectType            : ab721a53-1e2f-11d0-9819-00aa0040529b
InheritedObjectType   : bf967a86-0de6-11d0-a285-00aa003049e2
ObjectFlags           : ObjectAceTypePresent, InheritedObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : False
InheritanceFlags      : ContainerInherit
PropagationFlags      : InheritOnly

--- Create new Computer Object ---
ActiveDirectoryRights : CreateChild
InheritanceType       : All
ObjectType            : bf967a86-0de6-11d0-a285-00aa003049e2
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : ObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : <JoinIdentity>
IsInherited           : True
InheritanceFlags      : ContainerInherit
PropagationFlags      : None


bf967a86-0de6-11d0-a285-00aa003049e2 - Computer Object GUID


Finding the access rights -- https://blogs.msdn.microsoft.com/adpowershell/2009/09/22/how-to-find-extended-rights-that-apply-to-a-schema-class-object/

$inputObjectClass = "group"

$rootDSE = Get-ADRootDSE
$configNCDN = $rootDSE.ConfigurationNamingContext
$schemaNCDN = $rootDSE.SchemaNamingContext
$extendedRightsDN = "CN=Extended-Rights," + $configNCDN
$classObject = get-adobject -SearchBase $schemaNCDN -Filter { name -eq $inputObjectClass -and objectClass -eq "classSchema"} -Properties SchemaIDGUID
if ($classObject -ne $null) {

    $schemaIDGuid = [System.Guid] $classObject.SchemaIDGUID
    Get-ADObject -SearchBase $extendedRightsDN -Filter { appliesTo -eq $schemaIDGuid  } -Properties RightsGuid,cn,displayname | Select RightsGuid,cn,displayname

} else {

    Write-Error ("Specified class object not found! : " + $inputObjectClass)

}

 #>
