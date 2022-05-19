# Get-UnJlaive
Get-UnJlaive is tool which is able to reconstruct Jlaive (.NET Antivirus Evasion Tool (Exe2Bat)) to original Assembly and stub Assembly.<br/>
It should defeat even the obfuscated form.<br/>
Jlaive - https://github.com/ch2sh/Jlaive<br/>

## SYNOPSIS
Author: Dump-GUY (@vinopaljiri)<br/>
Get-UnJlaive is tool which is able to reconstruct Jlaive (.NET Antivirus Evasion Tool (Exe2Bat)) to original Assembly and stub Assembly.<br/>
Jlaive is an antivirus evasion tool that can convert .NET assemblies into undetectable batch files https://github.com/ch2sh/Jlaive.<br/>

## DESCRIPTION
Get-UnJlaive PS module uses dnlib to parse assembly and .NET reflection to load dnlib.<br/>
Jlaive protected .bat file is executed and immediately suspended-terminated to grab deobfuscated form of cmdline - when obfuscation was used<br/>
Run ONLY in your VM - malicious code should not be executated but for sure<br/>
If you want to run .bat file as elevated process run this module elevated<br/>
Tested version Jlaive v0.2.3<br/>

## PARAMETER PathToBATFile
Mandatory parameter.<br/>
Specifies the .bat file protected by Jlaive.<br/>

## EXAMPLE
PS> Import-Module .\Get-UnJlaive.ps1<br/>
PS> Get-UnJlaive -PathToBATFile ..\malicious.bat<br/>
PS> Get-UnJlaive -PathToBATFile "C:\Users\XXX\Desktop\malicious.bat"<br/>

## LINK
https://github.com/Dump-GUY/Get-UnJlaive<br/>
https://github.com/ch2sh/Jlaive<br/>
