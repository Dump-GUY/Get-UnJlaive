<#
.SYNOPSIS
Author: Dump-GUY (@vinopaljiri)
Get-UnJlaive is tool which is able to reconstruct Jlaive (.NET Antivirus Evasion Tool (Exe2Bat)) to original Assembly and stub Assembly.
Jlaive is an antivirus evasion tool that can convert .NET assemblies into undetectable batch files https://github.com/ch2sh/Jlaive.

.DESCRIPTION
Get-UnJlaive PS module uses dnlib to parse assembly and .NET reflection to load dnlib.
Jlaive protected .bat file is executed and immediately suspended-terminated to grab deobfuscated form of cmdline - when obfuscation was used
Run ONLY in your VM - malicious code should not be executated but for sure
If you want to run .bat file as elevated process run this module elevated
Tested version Jlaive v0.2.3

.PARAMETER PathToBATFile
Mandatory parameter.
Specifies the .bat file protected by Jlaive.

.EXAMPLE
PS> Import-Module .\Get-UnJlaive.ps1
PS> Get-UnJlaive -PathToBATFile ..\malicious.bat
PS> Get-UnJlaive -PathToBATFile "C:\Users\XXX\Desktop\malicious.bat"

.LINK
https://github.com/Dump-GUY/Get-UnJlaive
https://github.com/ch2sh/Jlaive
#>

#if elevated process run this module elevated
function Get-UnJlaive
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PathToBATFile
    )

	#loading dnlib - for parsing stub_assembly
	[System.Reflection.Assembly]::Load($dnlib) | Out-Null

	#Functionality to suspend and terminate processes
	Add-Type -Name Threader -Namespace "" -Member @"
		[Flags]
		public enum ProcessAccess : uint
		{
			Terminate = 0x00000001,
			CreateThread = 0x00000002,
			VMOperation = 0x00000008,
			VMRead = 0x00000010,
			VMWrite = 0x00000020,
			DupHandle = 0x00000040,
			SetInformation = 0x00000200,
			QueryInformation = 0x00000400,
			SuspendResume = 0x00000800,
			Synchronize = 0x00100000,
			All = 0x001F0FFF
		}

		[DllImport("ntdll.dll", EntryPoint = "NtSuspendProcess", SetLastError = true)]
		public static extern uint SuspendProcess(IntPtr processHandle);

		[DllImport("ntdll.dll", EntryPoint = "NtTerminateProcess", SetLastError = true)]
		public static extern uint TerminateProcess(IntPtr hProcess, int errorStatus);

		[DllImport("kernel32.dll")]
		public static extern IntPtr OpenProcess(ProcessAccess dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

		[DllImport("kernel32.dll", SetLastError=true)]
		public static extern bool CloseHandle(IntPtr hObject);
"@

	function Suspend-Process($processID) {
		if(($pProc = [Threader]::OpenProcess("SuspendResume", $false, $processID)) -ne [IntPtr]::Zero){
			Write-Host "Trying to suspend process: $processID"
			$result = [Threader]::SuspendProcess($pProc)
			if($result -ne 0) {
				Write-Error "Failed to suspend. SuspendProcess returned: $result"
				return $False
			}
			[Threader]::CloseHandle($pProc) | out-null;
		} else {
			Write-Error "Unable to open process. Not elevated? Process doesn't exist anymore?"
			return $False
		}
		return $True
	}
	function Exit-Process($processID) {
		if(($pProc = [Threader]::OpenProcess("Terminate", $false, $processID)) -ne [IntPtr]::Zero){
			Write-Host "Trying to terminate process: $processID"
			$result = [Threader]::TerminateProcess($pProc, 0)
			if($result -ne 0) {
				Write-Error "Failed to terminate. TerminateProcess returned: $result"
				return $false
			}
			[Threader]::CloseHandle($pProc) | out-null
			return $true
		} else {
			Write-Error "Unable to open process. Process doesn't exist anymore?"
			return $false
		}
	}
	#aes decryption
	function Aes_Decrypt([byte[]]$input_bytes, [byte[]]$key, [byte[]]$iv)
	{
		$AesManaged = [System.Security.Cryptography.AesManaged]::new()
		$AesManaged.Mode = [System.Security.Cryptography.CipherMode]::CBC
		$AesManaged.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
		$AesDecryptor = $AesManaged.CreateDecryptor($key, $iv)
		$decrypted_bytes = $AesDecryptor.TransformFinalBlock($input_bytes, 0, $input_bytes.length)
		$AesDecryptor.Dispose()
		$aesmanaged.Dispose()
		return $decrypted_bytes
	}
	#gzip decompression
	function GunZip([byte[]]$input_bytes)
	{
		$msi = [System.IO.MemoryStream]::new($input_bytes)
		$mso = [System.IO.MemoryStream]::new()
		$decompress = [System.IO.Compression.GZipStream]::new($msi, [System.IO.Compression.CompressionMode]::Decompress)
		$decompress.CopyTo($mso)
		$decompressed_bytes = $mso.ToArray()
		$msi.Dispose()
		$msi.Dispose()
		$decompress.Dispose()

		return $decompressed_bytes
	}
	#find all "string" occurences
	function AllIndexesOf($str, $string_value) 
	{
		$indexes = @()
		for ($index = 0;; $index += $string_value.Length) {
			$index = $str.IndexOf($string_value, $index);
			if ($index -eq -1)
			{
				return $indexes;
			}           
			$indexes += $index + $string_value.Length;
		}
	}

	#parsing assembly_stub via dnlib to get original assembly aes key, iv, resource name
	function Parse-StubAssembly($ModuleDefMD)
	{	$AllTypes = $ModuleDefMD.GetTypes()
		$strings = @()
		foreach($type in $AllTypes)
		{   
			foreach($method in $type.Methods)
			{   #get only Methods with PinvokeImpl attribute
				if($method.name -like "Main")
				{   
					foreach ($instruction in $method.MethodBody.Instructions)
					{
						if($instruction.OpCode -eq [dnlib.DotNet.Emit.OpCodes]::Ldstr)
						{
							$strings += $instruction.Operand
						}
					}
					return $strings[-3..-1]	#returns resourse name, aeskey, aesIV			
				}
			}
		}
		return $false
	}

	#gets encrypted stub_assembly - last line of bat
	$bat_content = [System.IO.File]::ReadAllText($PathToBATFile)
	$encrypted_stub_bytes = [System.Convert]::FromBase64String(($bat_content.Split([Environment]::NewLine))[-1])

	#Functionality to monitor newly created processes suspend, grab cmdline and kill -> dealing with obfuscated one
	$culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
	[System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture
	[System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
	$new_process_check_interval = New-Object System.TimeSpan(0,0,0,0,50) #public TimeSpan (int days, int hours, int minutes, int seconds, int milliseconds)
	Write-Host "Monitoring processes...`n"

	$scope = New-Object System.Management.ManagementScope("\\.\root\cimV2")
	$query = New-Object System.Management.WQLEventQuery("__InstanceCreationEvent",$new_process_check_interval,"TargetInstance ISA 'Win32_Process'" )
	$watcher = New-Object System.Management.ManagementEventWatcher($scope,$query)
	$CommandLine = ""
	#executing .bat file to capture cmdline 
	Write-Host "Executing $PathToBATFile to capture deobfuscated cmdline."
	Start-Process PowerShell.exe -ArgumentList "-Command", "Start-Sleep 3; Start-Process $($PathToBATFile)" -WindowStyle Hidden
	do
	{
		$newlyArrivedEvent = $watcher.WaitForNextEvent(); #Synchronous call! If Control+C is pressed to stop the PowerShell script, PS will only react once the call has returned an event.
		$e = $newlyArrivedEvent.TargetInstance;

		if ($e.CommandLine -like "*FromBase64String*")
		{
			if(Suspend-Process -processID $e.ProcessId)
			{
				Write-Host "Suspicious Process is suspended."
				Write-Host "Deobfuscated cmdline grabbed."
				$CommandLine =  $e.CommandLine

				if(Exit-Process -processID $e.ProcessId)
				{
					Write-Host "Suspicious Process is Terminated.`n"
					break
				}
			}
		}
	} while ($true)

	#extracting of Password and IV from catched deobfuscated cmdline
	$indexes_base64 = AllIndexesOf -str $CommandLine -string_value "FromBase64String('"
	$aes_key_stub = $CommandLine.Substring($indexes_base64[1], ($CommandLine.Substring($indexes_base64[1])).IndexOf("')", 0))
	$aes_IV_stub = $CommandLine.Substring($indexes_base64[2], ($CommandLine.Substring($indexes_base64[2])).IndexOf("')", 0))
	$decrypted_stub_bytes = Aes_Decrypt -input_bytes $encrypted_stub_bytes -key ([System.Convert]::FromBase64String($aes_key_stub)) -iv ([System.Convert]::FromBase64String($aes_IV_stub))
	[byte[]]$assembly_stub = GunZip -input_bytes $decrypted_stub_bytes

	#parsing assembly_stub via dnlib to get original assembly resource name, aes key, iv in this order
	$ModuleDefMD = [dnlib.DotNet.ModuleDefMD]::Load($assembly_stub)
	$parsed_strings = Parse-StubAssembly -ModuleDefMD $ModuleDefMD

	if($parsed_strings)
	{
		$Resource_reader = $ModuleDefMD.Resources.Find($parsed_strings[0]).CreateReader()
		$resource_orig_assembly_encrypted = $Resource_reader.ReadString($Resource_reader.Length, [System.Text.Encoding]::UTF8)
		$aes_key_orig = $parsed_strings[1]
		$aes_IV_orig = $parsed_strings[2]
		$decrypted_orig = Aes_Decrypt -input_bytes ([System.Convert]::FromBase64String($resource_orig_assembly_encrypted)) -key ([System.Convert]::FromBase64String($aes_key_orig)) -iv ([System.Convert]::FromBase64String($aes_IV_orig))
		[byte[]]$assembly_orig = GunZip -input_bytes $decrypted_orig
		[System.IO.File]::WriteAllBytes("$PathToBATFile" + "_orig.exe", $assembly_orig)
		Write-Host ("Original assembly reconstructed: " + "$PathToBATFile" +"_orig.exe")
	}
	else
	{
		Write-Host "Could not parsed strings from Main methods of stub assembly!!!"
	}

	[System.IO.File]::WriteAllBytes("$PathToBATFile" +"_stub.exe", $assembly_stub)
	Write-Host ("Stub assembly reconstructed: " + "$PathToBATFile" +"_stub.exe")
	Write-Host "Finished!`n"
}
