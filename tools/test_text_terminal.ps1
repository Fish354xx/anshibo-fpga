$ErrorActionPreference='Stop'
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'uart_terminal.ps1'),[ref]$null,[ref]$null)
foreach($name in @('Send-Request','Send-Text')) {
 $function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 . ([scriptblock]::Create($function.Extent.Text))
}
$fontMap=New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
foreach($entry in (Get-Content (Join-Path $PSScriptRoot 'text_font.json') -Raw -Encoding UTF8 | ConvertFrom-Json)) {
 $fontMap.Add($entry.character,[int]$entry.id)
}
$sent=New-Object 'System.Collections.Generic.List[string]'
$serial=New-Object PSObject
$serial|Add-Member ScriptMethod WriteLine {param($text) $sent.Add($text)}
$serial|Add-Member ScriptMethod ReadLine { 'OK '+($sent[$sent.Count-1] -split ' ')[0] }
Send-Text 'Aa'
if(($sent -join '|') -ne 'TBEGIN|TCHAR 021|TCHAR 041|TCOMMIT'){throw 'Case preservation failed'}
$sent.Clear()
Send-Text ([string][char]0x4ECA)
if(($sent -join '|') -ne 'TBEGIN|TCHAR 05F|TCOMMIT'){throw 'Chinese mapping failed'}
$sent.Clear()
Send-Text ([string][char]0x9F98)
if($sent.Count -ne 0){throw 'Unsupported text reached FPGA'}
Send-Text ('A'*65)
if($sent.Count -ne 0){throw 'Oversized text reached FPGA'}
'TEXT TERMINAL: ALL CHECKS PASSED'
