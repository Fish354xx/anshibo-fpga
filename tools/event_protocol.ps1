# Human input is encoded as one staged event; FPGA owns validation and display.
function Get-EventCrc([byte[]]$Bytes) {
    $crc = 65535
    foreach ($octet in $Bytes) {
        $crc = $crc -bxor ([int]$octet -shl 8)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 32768) -ne 0) { $crc = (($crc -shl 1) -bxor 4129) -band 65535 }
            else { $crc = ($crc -shl 1) -band 65535 }
        }
    }
    return $crc
}
function New-EventPacket([int]$Id,[int]$Level,[string]$Area,[string]$Body) {
    if ($Id -lt 1 -or $Id -gt 65535 -or $Level -lt 1 -or $Level -gt 3) { throw 'ID must be 1..65535; level must be 1..3.' }
    if ([string]::IsNullOrWhiteSpace($Area) -or $Area.Length -gt 16) { throw 'Area must contain 1..16 characters.' }
    if ([string]::IsNullOrWhiteSpace($Body) -or $Body.Length -gt 64) { throw 'Message must contain 1..64 characters.' }
    $characters = ($Area+$Body).ToCharArray()
    $unknown = @($characters | ForEach-Object {[string]$_} | Where-Object {!$fontMap.ContainsKey($_)} | Select-Object -Unique)
    if ($unknown.Count -gt 0) { throw ('Unsupported characters: '+($unknown -join ' ')+'. See SUPPORTED_TEXT.txt.') }
    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @(($Id -shr 8),($Id -band 255),$Level,$Area.Length,$Body.Length)) { $bytes.Add([byte]$value) }
    $lines.Add(('EBEGIN {0:X4} {1} {2:X2} {3:X2}' -f $Id,$Level,$Area.Length,$Body.Length))
    foreach ($character in $characters) {
        $glyph = $fontMap[[string]$character]
        $bytes.Add([byte]($glyph -shr 8)); $bytes.Add([byte]($glyph -band 255))
        $lines.Add(('ECHAR {0:X3}' -f $glyph))
    }
    $crc = Get-EventCrc $bytes.ToArray()
    $lines.Add(('ECOMMIT {0:X4}' -f $crc))
    return [PSCustomObject]@{Id=$Id;Level=$Level;Area=$Area;Body=$Body;Crc=$crc;Lines=$lines.ToArray()}
}
function Read-EventStatus {
    $reply = Send-Request 'ESTATUS'
    if ($reply -notmatch '^EVENT I=([0-9A-F]{4}) L=([0-3]) S=([0-3]) C=([0-9A-F]{4}) A=([0-9A-F]{2}) T=([0-9A-F]{2}) P=([01])$') { throw "Invalid event reply: $reply" }
    return [PSCustomObject]@{Id=[Convert]::ToInt32($Matches[1],16);Level=[int]$Matches[2];State=[int]$Matches[3];Crc=[Convert]::ToInt32($Matches[4],16);AreaLength=[Convert]::ToInt32($Matches[5],16);BodyLength=[Convert]::ToInt32($Matches[6],16);Pending=[int]$Matches[7];Raw=$reply}
}
function Show-EventStatus($Status) {
    $states=@('NONE','PENDING','APPLIED','BLOCKED BY LOCAL')
    Write-Host ('Event #{0}: level={1}; {2}; bank pending={3}' -f $Status.Id,$Status.Level,$states[$Status.State],$Status.Pending)
}
function Send-EventPacket($Packet) {
    $began = $false
    try {
        foreach ($line in $Packet.Lines) {
            $reply = Send-Request $line
            if ($line.StartsWith('EBEGIN ')) {
                if ($reply -ne 'OK EBEGIN') { throw "Begin rejected: $reply" }
                $began=$true
            } elseif ($line.StartsWith('ECHAR ')) {
                if ($reply -ne 'OK ECHAR') { throw "Character rejected: $reply" }
            } else {
                if ($reply -notin @('OK ACCEPT','OK DUP')) { throw "Commit rejected: $reply" }
                $began=$false; Write-Host "FPGA: $reply; event #$($Packet.Id)"
            }
        }
        for ($attempt=0;$attempt -lt 100;$attempt++) {
            $status = Read-EventStatus
            if ($status.Id -ne $Packet.Id) { throw 'Another event superseded this event; query ESTATUS.' }
            if ($status.State -ne 1) { Show-EventStatus $status; return $status }
            Start-Sleep -Milliseconds 100
        }
        Write-Host 'Accepted; display still pending. Query ESTATUS to check progress.'
    } catch [System.TimeoutException] {
        Write-Host 'Reply timeout: result is uncertain. Query ESTATUS or retry the same ID with identical content.'
        $serial.DiscardInBuffer()
    } catch {
        if ($began) { try { Send-Request 'EABORT' | Out-Null } catch {} }
        throw
    }
}
function Publish-EventWizard {
    if ($null -eq $script:nextEventId) { $script:nextEventId=([int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 65535)) }
    $suggested=$script:nextEventId
    if ($suggested -eq 0) {$suggested=1}
    $idText=Read-Host "Event ID 1..65535 (Enter=$suggested)"
    if ([string]::IsNullOrWhiteSpace($idText)) {$eventNumber=$suggested}
    else {$eventNumber=0;if(![int]::TryParse($idText,[ref]$eventNumber)){throw 'Invalid decimal event ID.'}}
    $levelText=Read-Host 'Alert level 1 / 2 / 3'
    $eventLevel=0;if(![int]::TryParse($levelText,[ref]$eventLevel)){throw 'Invalid alert level.'}
    $areaText=Read-Host 'Area (1..16 characters)'
    $bodyText=Read-Host 'Emergency message (1..64 characters)'
    $packet=New-EventPacket $eventNumber $eventLevel $areaText.Trim() $bodyText.Trim()
    $script:nextEventId=($eventNumber+1) -band 65535
    if ($script:nextEventId -eq 0) {$script:nextEventId=1}
    Write-Host ('Publishing #{0}, level={1}, area={2}, CRC={3:X4}' -f $packet.Id,$packet.Level,$packet.Area,$packet.Crc)
    Send-EventPacket $packet | Out-Null
}
function Clear-Event([int]$Id) {
    $reply=Send-Request ('ECLEAR {0:X4}' -f $Id)
    Write-Host "FPGA: $reply"
    if ($reply -eq 'OK ECLEAR') { Write-Host 'Remote event cleared. Local alerts remain independent.' }
}


