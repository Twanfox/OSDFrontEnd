Param(
    [string]
    $Path,

    [System.Security.Cryptography.X509Certificates.X509Certificate2]
    $Certificate,

    [string]
    $ManifestName
)

Function Get-FileSignature {
    Param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        [string]
        $FileName
    )
    
    # https://blogs.msdn.microsoft.com/alejacma/2008/06/25/how-to-sign-and-verify-the-signature-with-net-and-a-certificate-c/

    if (Test-Path $FileName) {
        $Data = Get-Content $FileName
    } else {
        throw "Invalid filename specified"
    }

    [System.Security.Cryptography.RSACryptoServiceProvider] $CryptoProvider = $Certificate.PrivateKey
    
    if ($CryptoProvider -eq $null) {
        throw "Cannot generate file signature without a private key"
    }

    $Sha1 = New-Object System.Security.Cryptography.SHA1Managed
    $ByteStream = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $Hash = $Sha1.ComputeHash($ByteStream)

    Write-Output ([System.Convert]::ToBase64String($CryptoProvider.SignHash($Hash, [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA1"))))
}

##########
##
## Main Script Body
##
##########

if (-not (Test-Path $Path)) {
    throw "Unable to locate the specified path: $Path"
}

$FileList = Get-ChildItem -Path $Path -File | where Name -ne $ManifestName

$ManifestXml = New-Object System.Xml.XmlDocument
$ManifestXml.AppendChild($ManifestXml.CreateXmlDeclaration('1.0', 'utf-8', $null)) | Out-Null
$ManifestXml.AppendChild($ManifestXml.CreateElement("ContentPanelManifest")) | Out-Null
$ManifestXml.LastChild.Attributes.Append($ManifestXml.CreateAttribute("xmlns")) | Out-Null

foreach ($File in $FileList) {
    $FileXml = $ManifestXml.CreateElement("File")
    foreach ($Attribute in @('Name', 'Length', 'LastWriteTime')) {
        $FileXml.AppendChild($ManifestXml.CreateElement($Attribute)) | Out-Null
        if ($File."$Attribute" -ne $null) {
            $Value = $File."$Attribute".ToString()
            $FileXml.LastChild.AppendChild($ManifestXml.CreateTextNode($Value)) | Out-Null
        }
    }

    try {
        $FileXml.AppendChild($ManifestXml.CreateElement("Thumbprint")) | Out-Null
        $FileXml.LastChild.AppendChild($ManifestXml.CreateTextNode($Certificate.Thumbprint)) | Out-Null

        $FileXml.AppendChild($ManifestXml.CreateElement("FileSignature")) | Out-Null
        $Signature = Get-FileSignature -Certificate $Certificate -FileName $File.FullName
        $FileXml.LastChild.AppendChild($ManifestXml.CreateTextNode($Signature)) | Out-Null

        $ManifestXml.DocumentElement.AppendChild($FileXml) | Out-Null

        Write-Host "Successfully processed file $($File.Name)"
    } catch {
        Write-Error "Could not generate file signature for file $($File.Name). Skipping in Manifest"
    }
}

$ManifestFullPath = (Join-Path (Resolve-Path $Path).ProviderPath $ManifestName)
$ManifestXml.Save($ManifestFullPath)
Write-Host "Successfully saved manifest to $ManifestFullPath"
