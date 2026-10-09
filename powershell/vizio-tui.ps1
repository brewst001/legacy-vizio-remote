#requires -Version 5.1
<# Independent local TV settings menu. No Schannel, Python or WSL required. #>
param([string]$TvAddress='', [int]$Port=9000, [string]$JavaPath='java', [switch]$LibraryOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:IsWindowsHost=($env:OS -eq 'Windows_NT')
$script:TvAddress=$TvAddress
$script:ApiPort=$Port
$script:Token=''
$script:Legacy=$true
$script:Pins=@{}
$script:JavaExecutable=$JavaPath
$separator=[IO.Path]::PathSeparator
$dependencyDir=Join-Path $PSScriptRoot 'lib'
if (-not (Test-Path (Join-Path $dependencyDir 'bcprov-jdk18on-1.86.jar'))) { $dependencyDir=Join-Path (Split-Path $PSScriptRoot) 'app/libs' }
$script:ClassPath=(Join-Path $PSScriptRoot 'lib/transport.jar')+$separator+(Join-Path $dependencyDir '*')
$script:ConfigDir=if($script:IsWindowsHost){Join-Path $env:LOCALAPPDATA 'LegacyVizioRemote'}else{Join-Path $HOME '.config/legacy-vizio-powershell'}
$script:ConfigFile=Join-Path $script:ConfigDir 'connection.json'
$script:TrustFile=Join-Path $script:ConfigDir 'trusted-certificates.json'
function Get-Field($Object,[string]$Name,$Default=$null) {
 if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name};return $Default
}
function Get-PlainToken([Security.SecureString]$Secure) {
 $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
 try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
}
function Save-PrivateJson([string]$Path,$Object) {
 [IO.Directory]::CreateDirectory($script:ConfigDir)|Out-Null
 if($script:IsWindowsHost){
  $acl=New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true,$false)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit, ObjectInherit','None','Allow')
  $acl.AddAccessRule($rule);Set-Acl -LiteralPath $script:ConfigDir -AclObject $acl
 }
 $temp=Join-Path $script:ConfigDir ([Guid]::NewGuid().ToString()+'.tmp')
 try{
  [IO.File]::WriteAllText($temp,($Object|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  if(-not $script:IsWindowsHost){& chmod 600 $temp;if($LASTEXITCODE -ne 0){throw 'Unable to protect config file'}}
  if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,$null)}else{[IO.File]::Move($temp,$Path)}
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Invoke-Transport([string]$Method,[string]$Path,$Body=$null,[string]$Certificate='') {
 $payload=if($null -eq $Body){''}else{$Body|ConvertTo-Json -Compress -Depth 20}
 $fields=@($script:TvAddress,[string]$script:ApiPort,$script:Token,$Certificate,[string]$script:Legacy,$Method,$Path,$payload)
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$script:JavaExecutable
 # Only the fixed classpath appears on the command line; request fields use stdin.
 $start.Arguments='-cp "'+$script:ClassPath+'" net.local.vizioremote.TransportCli'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$start
 try{
  if(-not $process.Start()){throw 'Unable to start Java'}
  foreach($field in $fields){$process.StandardInput.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$field)))}
  $process.StandardInput.Close()
  $outputTask=$process.StandardOutput.ReadToEndAsync();$errorTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(25000)){$process.Kill();throw 'TV request timed out'}
  $output=$outputTask.GetAwaiter().GetResult();$detail=$errorTask.GetAwaiter().GetResult()
  if([string]::IsNullOrWhiteSpace($output)){throw "Java transport failed: $detail"}
  return $output|ConvertFrom-Json
 }finally{$process.Dispose()}
}
function Invoke-Tv([string]$Method,[string]$Path,$Body=$null) {
 $endpoint=$script:TvAddress+':'+$script:ApiPort
 $pin=if($script:Pins.ContainsKey($endpoint)){$script:Pins[$endpoint]}else{''}
 $reply=Invoke-Transport $Method $Path $Body $pin
 $data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reply.data))
 if($reply.kind -eq 'trust'){
  if($data -notmatch '^[A-F0-9]{64}$'){throw 'Invalid certificate fingerprint'}
  Write-Host "First connection to $endpoint. Certificate SHA-256: $data"
  Write-Host 'Confirm this is your TV on a trusted local network. Manufacturer certificates may be shared between TVs.'
  if((Read-Host 'Type TRUST to remember this certificate') -cne 'TRUST'){throw 'Certificate was not trusted'}
  $script:Pins[$endpoint]=$data;Save-PrivateJson $script:TrustFile $script:Pins
  $reply=Invoke-Transport $Method $Path $Body $data
  $data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reply.data))
 }
 if($reply.kind -ne 'ok'){throw $data}
 $result=$data|ConvertFrom-Json
 if((Get-Field (Get-Field $result 'STATUS') 'RESULT' '') -ne 'SUCCESS'){throw "TV rejected request: $($result|ConvertTo-Json -Compress -Depth 12)"}
 return $result
}
function Save-Connection {
 if((Read-Host 'Save this connection on this Windows account? [y/N]') -ne 'y'){return}
 if(-not $script:IsWindowsHost){throw 'Saved tokens are supported only on Windows; no plaintext fallback is provided'}
 $protected=if($script:Token){ConvertFrom-SecureString (ConvertTo-SecureString $script:Token -AsPlainText -Force)}else{''}
 Save-PrivateJson $script:ConfigFile @{host=$script:TvAddress;port=$script:ApiPort;legacy=$script:Legacy;protected_token=$protected}
}
function Set-Connection {
 $address=Read-Host "TV private IPv4 address [$($script:TvAddress)]"
 if($address){$script:TvAddress=$address.Trim()}
 $value=Read-Host "API port [$($script:ApiPort)]"
 if($value){$script:ApiPort=[int]$value}
 if($script:ApiPort -lt 1 -or $script:ApiPort -gt 65535){throw 'Invalid port'}
 $script:Legacy=((Read-Host 'Legacy TLS compatibility? [Y/n]') -ne 'n')
 $option=Read-Host 'Authentication: 1 existing token, 2 pair'
 if($option -eq '2'){
  $script:Token='';$id='powershell-'+[Guid]::NewGuid().ToString()
  $reply=Invoke-Tv PUT '/pairing/start' @{DEVICE_ID=$id;DEVICE_NAME='PowerShell TV Menu'}
  $challenge=$reply.ITEM
  $code=Read-Host 'Current four-digit TV PIN (Play/Pause may reveal a hidden PIN)'
  if($code -notmatch '^\d{4}$'){throw 'Expected four digits; start a fresh pairing attempt'}
  $reply=Invoke-Tv PUT '/pairing/pair' @{DEVICE_ID=$id;CHALLENGE_TYPE=$challenge.CHALLENGE_TYPE;PAIRING_REQ_TOKEN=$challenge.PAIRING_REQ_TOKEN;RESPONSE_VALUE=$code}
  $script:Token=[string]$reply.ITEM.AUTH_TOKEN;Write-Host 'Paired.'
 }elseif($option -eq '1'){$script:Token=Get-PlainToken (Read-Host 'Existing authentication token' -AsSecureString)}else{throw 'Choose 1 or 2'}
 Save-Connection
}
function Show-Json($Value) {
 $json=$Value|ConvertTo-Json -Depth 20;Write-Host $json
 if((Read-Host 'Copy JSON to clipboard? [y/N]') -eq 'y'){
  if(Get-Command Set-Clipboard -ErrorAction SilentlyContinue){Set-Clipboard -Value $json}else{Write-Host 'Clipboard command unavailable'}
 }
}
function Find-Setting($Response,[string]$Cname) {
 foreach($entry in @(Get-Field $Response 'ITEMS' @())){if((Get-Field $entry 'CNAME') -eq $Cname){return $entry}}
 throw 'Setting no longer exists'
}
function Edit-Setting([string]$Parent,[string]$Cname) {
 if($Cname -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid setting path'}
 $item=Find-Setting (Invoke-Tv GET $Parent) $Cname
 $type=[string](Get-Field $item 'TYPE' '')
 if(-not (Get-Field $item 'ENABLED' $false)){Show-Json $item;return}
 if($type -match '^T_MENU(_X)?_V1$'){Show-Menu ($Parent+'/'+$Cname) ([string]$item.NAME);return}
 if($type -notin @('T_LIST_V1','T_LIST_X_V1','T_VALUE_V1','T_VALUE_ABS_V1','T_STRING_V1','T_IP_ADDRESS_V1')){Show-Json $item;return}
 $choices=@(Get-Field $item 'ELEMENTS' @())
 if($choices.Count -gt 0){
  for($i=0;$i -lt $choices.Count;$i++){
   if($choices[$i] -isnot [string] -and $choices[$i] -isnot [ValueType]){Show-Json $item;return}
   Write-Host "$($i+1). $($choices[$i])"
  }
  $selected=Read-Host 'Choose value number, or Enter to cancel'
  if(-not $selected){return}
  $number=0;if(-not [int]::TryParse($selected,[ref]$number) -or $number -lt 1 -or $number -gt $choices.Count){throw 'Invalid selection'}
  $next=$choices[$number-1]
 }elseif($type -like 'T_LIST*'){Show-Json $item;return}
 else{
  $current=Get-Field $item 'VALUE'
  $text=Read-Host "New value (current: $current); Enter cancels"
  if($text -eq ''){return}
  if($current -is [bool]){if($text -notin @('true','false')){throw 'Enter true or false'};$next=($text -eq 'true')}
  elseif($current -is [ValueType]){$next=[decimal]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)}
  elseif($current -is [string]){$next=$text}else{Show-Json $item;return}
 }
 if((Read-Host "Change $($item.NAME) from '$($item.VALUE)' to '$next'? [y/N]") -ne 'y'){return}
 $fresh=Find-Setting (Invoke-Tv GET $Parent) $Cname
 if(-not (Get-Field $fresh 'ENABLED' $false)){throw 'Setting is now unavailable'}
 if(($fresh.VALUE|ConvertTo-Json -Compress) -cne ($item.VALUE|ConvertTo-Json -Compress)){throw 'Value changed while editing; refresh and retry'}
 $allowed=@(Get-Field $fresh 'ELEMENTS' @())
 if($allowed.Count -gt 0 -and $next -notin $allowed){throw 'Choice is no longer available'}
 $hash=Get-Field $fresh 'HASHVAL';if($null -eq $hash){throw 'Missing setting hash'}
 if($next -is [ValueType] -and $next -isnot [bool]){
  $minimum=Get-Field $fresh 'MINIMUM';$maximum=Get-Field $fresh 'MAXIMUM'
  if(($null -ne $minimum -and $next -lt $minimum) -or ($null -ne $maximum -and $next -gt $maximum)){throw 'Value outside advertised range'}
 }
 Invoke-Tv PUT ($Parent+'/'+$Cname) @{REQUEST='MODIFY';HASHVAL=$hash;VALUE=$next}|Out-Null
 Write-Host 'Updated.'
}
function Show-Menu([string]$Path,[string]$Title) {
 while($true){
  $reply=Invoke-Tv GET $Path;$items=@(Get-Field $reply 'ITEMS' @())
  Write-Host "`n$Title -- Enter returns; J shows JSON"
  for($i=0;$i -lt $items.Count;$i++){
   $entry=$items[$i];$value=if((Get-Field $entry 'TYPE' '') -like 'T_MENU*'){'[submenu]'}else{Get-Field $entry 'VALUE'}
   $suffix=if(Get-Field $entry 'ENABLED' $false){''}else{' [unavailable]'}
   Write-Host "$($i+1). $($entry.NAME): $value$suffix"
  }
  $choice=Read-Host 'Selection';if(-not $choice){return};if($choice -eq 'j'){Show-Json $reply;continue}
  $number=0
  if([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $items.Count){
   try{Edit-Setting $Path ([string]$items[$number-1].CNAME)}catch{Write-Host $_.Exception.Message -ForegroundColor Red}
  }else{Write-Host 'Invalid selection'}
 }
}
if($LibraryOnly){return}
if(-not (Test-Path (Join-Path $PSScriptRoot 'lib/transport.jar'))){throw 'Extract the complete release ZIP, including lib/transport.jar'}
if(Test-Path $script:TrustFile){
 $saved=Get-Content -LiteralPath $script:TrustFile -Raw|ConvertFrom-Json
 foreach($property in $saved.PSObject.Properties){if($property.Value -notmatch '^[A-F0-9]{64}$'){throw 'Invalid trusted certificate file; refusing connection'};$script:Pins[$property.Name]=[string]$property.Value}
}
if(Test-Path $script:ConfigFile){
 $saved=Get-Content -LiteralPath $script:ConfigFile -Raw|ConvertFrom-Json
 if(-not $TvAddress){$script:TvAddress=[string]$saved.host}
 if(-not $PSBoundParameters.ContainsKey('Port')){$script:ApiPort=[int]$saved.port}
 $script:Legacy=[bool]$saved.legacy
 if($script:IsWindowsHost -and $saved.protected_token){$script:Token=Get-PlainToken (ConvertTo-SecureString $saved.protected_token)}
}
Write-Host 'Legacy Vizio PowerShell menu -- provided as-is without support.'
if(-not $script:Token){Set-Connection}
$categories=@('system','picture','audio','timers','network','devices','channels','closed_captions','mobile_devices','cast')
while($true){
 Write-Host "`nTV: $($script:TvAddress):$($script:ApiPort)"
 for($i=0;$i -lt $categories.Count;$i++){Write-Host "$($i+1). $($categories[$i])"}
 Write-Host 'V volume up | D volume down | M mute | P power state | C connection | F forget certificate | Q quit'
 $selection=Read-Host 'Selection'
 try{
  switch($selection.ToLowerInvariant()){
   'q' {return}
   'c' {Set-Connection;continue}
   'f' {$endpoint=$script:TvAddress+':'+$script:ApiPort;if((Read-Host "Forget certificate for $endpoint after verifying the TV? Type FORGET") -ceq 'FORGET'){$script:Pins.Remove($endpoint);Save-PrivateJson $script:TrustFile $script:Pins};continue}
   'p' {Show-Json (Invoke-Tv GET '/state/device/power_mode');continue}
   'v' {Invoke-Tv PUT '/key_command/' @{KEYLIST=@(@{CODESET=5;CODE=1;ACTION='KEYPRESS'})}|Out-Null;continue}
   'd' {Invoke-Tv PUT '/key_command/' @{KEYLIST=@(@{CODESET=5;CODE=0;ACTION='KEYPRESS'})}|Out-Null;continue}
   'm' {Invoke-Tv PUT '/key_command/' @{KEYLIST=@(@{CODESET=5;CODE=4;ACTION='KEYPRESS'})}|Out-Null;continue}
  }
  $number=0;if([int]::TryParse($selection,[ref]$number) -and $number -ge 1 -and $number -le $categories.Count){Show-Menu ('/menu_native/dynamic/tv_settings/'+$categories[$number-1]) $categories[$number-1]}
 }catch{Write-Host $_.Exception.Message -ForegroundColor Red}
}
