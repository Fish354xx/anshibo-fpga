$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'event_protocol.ps1')
$fontMap=New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
foreach($entry in (Get-Content (Join-Path $PSScriptRoot 'text_font.json') -Raw -Encoding UTF8 | ConvertFrom-Json)){$fontMap.Add($entry.character,[int]$entry.id)}
if((Get-EventCrc ([Text.Encoding]::ASCII.GetBytes('123456789'))) -ne 10673){throw 'CRC reference failed'}
$packet=New-EventPacket 1 1 'AB' 'CDE'
if($packet.Crc -ne 33980 -or ($packet.Lines -join '|') -ne 'EBEGIN 0001 1 02 03|ECHAR 021|ECHAR 022|ECHAR 023|ECHAR 024|ECHAR 025|ECOMMIT 84BC'){throw 'Packet encoding failed'}
$invalid=$false;try{New-EventPacket 2 1 'A' ('x'*65)|Out-Null}catch{$invalid=$true};if(!$invalid){throw 'Length check failed'}
$invalid=$false;try{New-EventPacket 2 1 'A' ([string][char]0x9F98)|Out-Null}catch{$invalid=$true};if(!$invalid){throw 'Unknown glyph check failed'}
$invalid=$false;try{New-EventPacket 2 1 ' ' 'A'|Out-Null}catch{$invalid=$true};if(!$invalid){throw 'Blank area check failed'}
$sent=New-Object 'System.Collections.Generic.List[string]'
function Send-Request([string]$Command){
 $sent.Add($Command)
 if($Command.StartsWith('EBEGIN ')){return 'OK EBEGIN'}
 if($Command.StartsWith('ECHAR ')){return 'OK ECHAR'}
 if($Command.StartsWith('ECOMMIT ')){return 'OK ACCEPT'}
 if($Command -eq 'ESTATUS'){return 'EVENT I=0001 L=1 S=2 C=84BC A=02 T=03 P=0'}
 throw 'Unexpected mock command'
}
$status=Send-EventPacket $packet
if($status.State -ne 2 -or $sent.Count -ne 8){throw 'Acceptance/display flow failed'}
'EVENT PROTOCOL TOOL: ALL CHECKS PASSED'
