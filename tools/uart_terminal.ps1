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
    if ($Response -match '^STATUS D=([0-9A-F]{4}) S=([0-9A-F]) P=([0-9A-F]{2})(?: A=([01]) O=([01]) R=([0-7]))?$') {
        $debugWord = [Convert]::ToInt32($Matches[1], 16)
        $stateValue = [Convert]::ToInt32($Matches[2], 16)
        $settingsValue = [Convert]::ToInt32($Matches[3], 16)
        $autoValue = $Matches[4]
        $overlayValue = $Matches[5]
        $ownershipValue = $Matches[6]
        Write-Host ('Images={0}; image index={1} (zero-based); emergency={2}; loading={3}; scan done={4}' -f (($debugWord -shr 12) -band 7),(($debugWord -shr 8) -band 3),($debugWord -band 1),(($debugWord -shr 1) -band 1),(($debugWord -shr 3) -band 1))
        Write-Host ('Adjustment={0}; select contrast={1}; brightness={2}/4; contrast={3}/4; state={4}' -f (($settingsValue -shr 7) -band 1),(($settingsValue -shr 6) -band 1),(($settingsValue -shr 3) -band 7),($settingsValue -band 7),$stateValue)
        if ($null -ne $autoValue) { Write-Host "Auto=$autoValue; overlay=$overlayValue; remote ownership mask=$ownershipValue (overlay=4, adjustment=2, selector=1)" }
    }
}
function Show-Help {
    Write-Host 'PING | STATUS | NEXT | SHOW 1 / SHOW 2 / SHOW 3'
    Write-Host 'AUTO ON / OFF | EMERGENCY ON / OFF'
    Write-Host 'BRIGHTNESS 0..4 / + / - | CONTRAST 0..4 / + / -'
    Write-Host 'ADJUST ON / OFF | SELECT BRIGHTNESS / CONTRAST'
    Write-Host 'OVERLAY ON / OFF | LOCAL | RESET | HELP | EXIT'
    Write-Host 'OVERLAY controls text and waveform together. LOCAL restores physical switch control.'
    Write-Host 'TEXT <content> updates scrolling subtitle (1..64 characters); TEXT DEFAULT restores built-in text.'
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
        if ($command -match '^TEXT\s+DEFAULT$') { $command = 'TDEFAULT' }
        elseif ($command -match '^TEXT\s+(.+)$') { Send-Text $Matches[1]; continue }
        $command = $command.ToUpperInvariant()
        if ($command -eq 'EXIT') { break }
        if ($command -eq '') { continue }
        if ($command -eq 'HELP') { Show-Help; continue }
        if ($command -notmatch '^(PING|STATUS|NEXT|LOCAL|RESET|TDEFAULT|SHOW [1-3]|(AUTO|EMERGENCY|ADJUST|OVERLAY) (ON|OFF)|SELECT (BRIGHTNESS|CONTRAST)|(BRIGHTNESS|CONTRAST) ([0-4]|\+|-))$') {
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

