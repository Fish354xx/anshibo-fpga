param([string]$Port)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ([string]::IsNullOrWhiteSpace($Port)) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    Write-Host 'Available COM ports:' ($ports -join ', ')
    $Port = Read-Host 'USB-UART COM port (for example COM5)'
}
$serial = New-Object System.IO.Ports.SerialPort $Port,115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 3000
$serial.WriteTimeout = 3000
$serial.NewLine = "`n"
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$fontMap = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
$fontData = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'text_font.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $fontData) { $fontMap.Add($entry.character,[int]$entry.id) }
. (Join-Path $PSScriptRoot 'event_protocol.ps1')
function Send-Request([string]$Command) {
    $serial.WriteLine($Command)
    return $serial.ReadLine().TrimEnd("`r")
}
function Send-Text([string]$Text) {
    if ($Text.Length -lt 1 -or $Text.Length -gt 64) {
        Write-Host 'Subtitle must contain 1..64 characters.'; return
    }
    $unknown = @($Text.ToCharArray() | ForEach-Object { [string]$_ } | Where-Object { !$fontMap.ContainsKey($_) } | Select-Object -Unique)
    if ($unknown.Count -gt 0) {
        Write-Host ('Unsupported characters: ' + ($unknown -join ' '))
        Write-Host 'See tools/SUPPORTED_TEXT.txt. Existing subtitle was not changed.'; return
    }
    try {
        $response = Send-Request 'TBEGIN'
        if ($response -ne 'OK TBEGIN') { Write-Host "FPGA: $response"; return }
        foreach ($character in $Text.ToCharArray()) {
            $response = Send-Request ('TCHAR {0:X3}' -f $fontMap[[string]$character])
            if ($response -ne 'OK TCHAR') { Write-Host "Upload stopped: $response"; return }
        }
        $response = Send-Request 'TCOMMIT'
        Write-Host "FPGA: $response"
        if ($response -eq 'OK TCOMMIT') { Write-Host "Subtitle queued for next frame: $Text" }
    } catch [System.TimeoutException] {
        Write-Host 'Subtitle upload timed out. Send PING and retry the entire TEXT command.'
        $serial.DiscardInBuffer()
    }
}
function Show-Status([string]$Response) {
    if($Response -match '^RES N=([0-9A-F]{2}) P=([0-9A-F]{2}) E=([01]) F=([0-9A-F]{2}) I=([0-9A-F]{2}) T=([0-9A-F]{2}) R=([01])$') {
        $files=[Convert]::ToInt32($Matches[1],16);$entries=[Convert]::ToInt32($Matches[2],16)
        $hasEmergency=$Matches[3];$flags=[Convert]::ToInt32($Matches[4],16)
        $slot=[Convert]::ToInt32($Matches[5],16);$seconds=[Convert]::ToInt32($Matches[6],16);$ready=$Matches[7]
        $position=if($slot -eq 16){'Emergency'}else{[string]($slot+1)}
        Write-Host "Daily files=$files; playback entries=$entries; position=$position; dwell=$seconds seconds; catalog ready=$ready"
        Write-Host "Emergency file=$hasEmergency (0 uses built-in fallback)"
        $flagNames=@('FAT32/IO error','No daily images','No emergency image','Invalid BMP skipped','Resource limit','Invalid playlist entry','Broken cluster chain','Runtime image error')
        if($flags -eq 0){Write-Host 'Resources OK'}
        else {for($bit=0;$bit -lt 8;$bit++){if($flags -band (1 -shl $bit)){Write-Host ('Resource issue: '+$flagNames[$bit])}}}
        return
    }
    if ($Response -match '^STATUS D=([0-9A-F]{4}) S=([0-9A-F]) P=([0-9A-F]{2})(?: A=([01]) O=([01]) R=([0-7]))?(?: E=([0-3]) B=([0-3]) M=([0-3]))?$') {
        $debugWord = [Convert]::ToInt32($Matches[1], 16)
        $stateValue = [Convert]::ToInt32($Matches[2], 16)
        $settingsValue = [Convert]::ToInt32($Matches[3], 16)
        $autoValue = $Matches[4]
        $overlayValue = $Matches[5]
        $ownershipValue = $Matches[6]
        $alertValue=$Matches[7];$boardAlert=$Matches[8];$remoteAlert=$Matches[9]
        Write-Host ('Emergency={0}; loading={1}; resources ready={2}. Use RESOURCES for daily count and current slot.' -f ($debugWord -band 1),(($debugWord -shr 1) -band 1),(($debugWord -shr 3) -band 1))
        Write-Host ('Adjustment={0}; select contrast={1}; brightness={2}/4; contrast={3}/4; state={4}' -f (($settingsValue -shr 7) -band 1),(($settingsValue -shr 6) -band 1),(($settingsValue -shr 3) -band 7),($settingsValue -band 7),$stateValue)
        if ($null -ne $autoValue) { Write-Host "Auto=$autoValue; overlay=$overlayValue; remote ownership mask=$ownershipValue (overlay=4, adjustment=2, selector=1)" }
        if ($null -ne $alertValue) { Write-Host "Alert effective=$alertValue; board=$boardAlert; remote=$remoteAlert" }
    }
}
function Show-Help {
    Write-Host 'PING | STATUS | RESOURCES | NEXT | SHOW 1..16 | ALERT 1 / 2 / 3 / CLEAR'
    Write-Host 'AUTO ON / OFF | EMERGENCY ON / OFF'
    Write-Host 'TRANSITION SLIDE / FADE / CUT | TRANSITION queries current setting'
    Write-Host 'BRIGHTNESS 0..4 / + / - | CONTRAST 0..4 / + / -'
    Write-Host 'ADJUST ON / OFF | SELECT BRIGHTNESS / CONTRAST'
    Write-Host 'OVERLAY ON / OFF | LOCAL | RESET | HELP | EXIT'
    Write-Host 'OVERLAY controls text and waveform together. LOCAL restores physical switch control.'
    Write-Host 'TEXT <content> updates scrolling subtitle (1..64 characters); TEXT DEFAULT restores built-in text.'
    Write-Host 'PUBLISH opens event entry: ID, level, area and emergency message.'
    Write-Host 'ESTATUS queries acceptance/display status. CLEAR [decimal ID] clears a remote event.'
}
try {
    $serial.Open()
    Write-Host "Connected: $Port, 115200 8N1, no flow control."
    Show-Help
    Write-Host 'Wait for each reply. OK NEXT acknowledges acceptance, not completed display.'
    while ($true) {
        $command = Read-Host 'Anshibo'
        if ($null -eq $command) { break }
        $command = $command.Trim()
        if ($command -eq 'PUBLISH') {
            try { Publish-EventWizard } catch { Write-Host $_.Exception.Message }
            continue
        }
        if ($command -eq 'ESTATUS') {
            try { Show-EventStatus (Read-EventStatus) } catch { Write-Host $_.Exception.Message }
            continue
        }
        if ($command -match '^CLEAR(?:\s+(\d{1,5}))?$') {
            try {
                $targetId=$Matches[1]
                if ([string]::IsNullOrWhiteSpace($targetId)) {
                    $status=Read-EventStatus
                    if ($status.State -eq 0) { Write-Host 'No active remote event.'; continue }
                    $targetId=$status.Id
                }
                if ([int]$targetId -lt 1 -or [int]$targetId -gt 65535) { throw 'Invalid decimal event ID.' }
                Clear-Event ([int]$targetId)
            } catch { Write-Host $_.Exception.Message }
            continue
        }
        if ($command -match '^TEXT\s+DEFAULT$') { $command = 'TDEFAULT' }
        elseif ($command -match '^TEXT\s+(.+)$') { Send-Text $Matches[1]; continue }
        $command = $command.ToUpperInvariant()
        if ($command -eq 'EXIT') { break }
        if ($command -eq '') { continue }
        if ($command -eq 'HELP') { Show-Help; continue }
        if ($command -notmatch '^(PING|STATUS|RESOURCES|NEXT|LOCAL|RESET|TDEFAULT|TRANSITION(?: (SLIDE|FADE|CUT))?|ALERT ([1-3]|CLEAR)|SHOW ([1-9]|1[0-6])|(AUTO|EMERGENCY|ADJUST|OVERLAY) (ON|OFF)|SELECT (BRIGHTNESS|CONTRAST)|(BRIGHTNESS|CONTRAST) ([0-4]|\+|-))$') {
            Write-Host 'Unknown command. Type HELP for the command list.'
            continue
        }
        $serial.WriteLine($command)
        try {
            $response = $serial.ReadLine().TrimEnd("`r")
            Write-Host "FPGA: $response"
            Show-Status $response
        } catch [System.TimeoutException] {
            Write-Host 'No reply: check USB-UART port, data cable and loaded bit file.'
            $serial.DiscardInBuffer()
        }
    }
} catch {
    Write-Host ('Serial error: ' + $_.Exception.Message)
    Read-Host 'Press Enter to close' | Out-Null
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}




