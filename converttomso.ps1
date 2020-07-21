$PrimaryDomain = Read-Host -Promt 'Please input the Primary Domain (@exmaple.com)'
$RoutingDomain = Read-Host -Promt 'Please input the Routing Domain (@exmaple.onmicrosoft.com)' 
$CSVPath = Read-Host -Promt 'Please envter the path of the csv guuid lookup table' 

function buildProxyAddresses {
    $mb = $args[0]
    $returnArray = @()

    $alias = $mb.Alias.toLower()

    $returnArray = $returnArray + ($alias + $PrimaryDomain)
    
    $givenName = ($mb.DistinguishedName | Select-String -Pattern '(?<=CN\=).+?(?=\s)').Matches.Value.toLower()
    $surname = ($mb.DistinguishedName | Select-String -Pattern 'CN\=.+?\s(.+?)\,').Matches.Groups[1].Value.toLower()

    $returnArray = $returnArray + ($givenName[0] + "." + $surname + $PrimaryDomain)
    $returnArray = $returnArray + ($givenName + "." + $surname[0] + $PrimaryDomain)

    $returnArray = $returnArray + ($givenName + "." + $surname + $PrimaryDomain)

    return $returnArray
}

function handleMailbox {
    $mb = $args[0]

    Disable-Mailbox -Identity $mb -Confirm:$False

    $rraddr = $mb.Alias + $RoutingDomain
    $psaddr = $am.Alias + $PrimaryDomain

    $csv = Import-Csv $CSVPath
    $exchangeguid = $csv | where UserPrincipalName -eq $mb.UserPrincipalName | Select -Property ExchangeGuid

    $emailAdresses = ($mb.EmailAddresses | %{ if ($_.Prefix.DisplayName -eq "SMTP") { $_ } else {} } | select SmtpAddress).SmtpAddress.ToLower();
    $calculatedEmailAdresses = buildProxyAddresses $mb

    $finalAddresses = [System.Collections.ArrayList]$emailAdresses;

    $calculatedEmailAdresses | %{ $finalAddresses.remove($_) }


    if( $finalAddresses.Count -eq 0)
    {
        Enable-RemoteMailbox -Identity $mb -Alias $mb.Alias -RemoteRoutingAddress $rraddr -PrimarySmtpAddress $psaddr
    }
    else
    {
        $rawEmailAddresses = ($mb.EmailAddresses | %{ if ($_.Prefix.DisplayName -eq "SMTP") { $_ } else {} } | select SmtpAddress, IsPrimaryAddress)

        $emailStrings = $rawEmailAddresses | %{$smtpValue = "smtp:";if( $_.IsPrimaryAddress ) {$smtpValue = "SMTP:"}; $smtpValue + $_.SmtpAddress}

        $finalString = ""

        $emailStrings | %{ $finalString = $finalString + $_ + ","}

        $finalString + $rraddr

        Set-RemoteMailbox $mb -ExchangeGuid $exchangeguid -EmailAddressPolicyEnabled $False -EmailAddresses $finalString
    }

   
    Set-RemoteMailbox $mb -ExchangeGuid $exchangeguid -EmailAddressPolicyEnabled $True 
}

$discoveryMailboxes = Get-Mailbox | where name -match "DiscoverySearchMailbox \{[A-F0-9A-f]{8}\-[A-F0-9A-f]{4}\-[A-F0-9A-f]{4}\-[A-F0-9A-f]{4}\-[A-F0-9A-f]{12}\}" | select -Property name
$userMailBoxes = Get-Mailbox | %{if ( $discoveryMailboxes.Name -contains $_.Name ) {} else { $_ } }

$userMailBoxes | %{ handleMailbox $_ }