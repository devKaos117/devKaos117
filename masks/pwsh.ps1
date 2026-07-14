<#
	.SYNOPSIS
		... 
	.DESCRIPTION
		...
	.PARAMETER ...
		...
	.EXAMPLE
		...
	.INPUTS
		...
	.OUTPUTS
		...
	.COMPONENT
		...
	.LINK
		...
	.NOTES
		Author: https://www.linkedin.com/in/kaos/
		References:
#>
# ============================================================================
# INITIALIZATIONS
# ============================================================================
[CmdletBinding()]
[OutputType([System.Void])]
param(
	[ValidateSet("NONE", "CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG")]
	[string] $LogLevel = "INFO",

	[ValidateRange(1, [int]::MaxValue)]
	[int]$Rate = 10,

	[ValidateRange(1, [int]::MaxValue)]
	[int]$Period = 1,

	[ValidateRange(1, [int]::MaxValue)]
	[int]$MaxThreads = [Math]::Max([int]$env:NUMBER_OF_PROCESSORS, 1)
)

$ErrorActionPreference = "Stop"

# Try to execute script using PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
	$pwshPaths = @(
		"$Env:ProgramFiles\PowerShell\7\pwsh.exe",
		"$Env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe",
		"${Env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
		"$Env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
	)
	$pwshPath = $pwshPaths | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1

	if ($pwshPath) {
		Write-Host "[!] Relaunching script in PowerShell 7 using $pwshPath" -ForegroundColor Yellow
		& $pwshPath -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
		exit
	} else {
		Write-Host "[!] Failed to relaunch script in PowerShell 7" -ForegroundColor Red
	}
}

# Measure execution timing
$stopwatch = [system.diagnostics.stopwatch]::StartNew()

# ============================================================================
# UTILITIES
# ============================================================================
<#
	.SYNOPSIS
	.DESCRIPTION
	.PARAMETER None
	.EXAMPLE
	.INPUTS
	.OUTPUTS
		System.Void
	.COMPONENT
		Utilities
	.LINK
	.NOTES
		Date: July 2026
#>
function Write-Color {
	[CmdletBinding()]
	[OutputType([System.Void])]
	param(
		[Parameter(Mandatory)]
		[string]$Msg
	)
	process {
		# Default color
		$defaultColor = "White"	
		# Find pattern
		$pattern = '\{\{(?<color>\w+):(?<text>.*?)\}\}' # {{Color:Text}}
		$patternMatches = [regex]::Matches($Msg, $pattern)
		# Iterate through the message
		$lastIndex = 0
		foreach ($m in $patternMatches) {
			# Write text before match
			if ($m.Index -gt $lastIndex) {
				$plainText = $Msg.Substring($lastIndex, $m.Index - $lastIndex)
				Write-Host $plainText -NoNewline -ForegroundColor $defaultColor
			}
			# Extract components
			$color = $m.Groups["color"].Value
			$txt = $m.Groups["text"].Value
			# Validate color
			if (-not [Enum]::GetNames([ConsoleColor]).Contains($color)) {
				$color = $defaultColor
			}
			# Write message segment
			Write-Host $txt -ForegroundColor $color -NoNewline
			$lastIndex = $m.Index + $m.Length
		}
		# Remaining text
		if ($lastIndex -lt $Msg.Length) {
			Write-Host $Msg.Substring($lastIndex) -NoNewline -ForegroundColor $defaultColor
		}
		# Final newline
		Write-Host ""
	}
}

# ============================================================================
# LOGGER
# ============================================================================
# ================ Constants
Set-Variable -Name TimestampFormat -Option Constant -Scope Script -Visibility Private -Value "HH:mm:ss.fff"
Set-Variable -Name LogValues -Option Constant -Scope Script -Visibility Private -Value @{
	"NONE" = 99
	"CRITICAL" = 50
	"ERROR" = 40
	"WARNING" = 30
	"INFO" = 20
	"DEBUG" = 10
}
Set-Variable -Name LogColors -Option Constant -Scope Script -Visibility Private -Value @{
	99 = "White"	# Reset/None
	50 = "Magenta"	# Critical
	40 = "Red"		# Error
	30 = "Yellow"	# Warning
	20 = "Green"	# Info
	10 = "Cyan"		# Debug
}

<#
	.SYNOPSIS
	.DESCRIPTION
	.PARAMETER None
	.EXAMPLE
	.INPUTS
	.OUTPUTS
		System.Void
	.COMPONENT
		Logger
	.LINK
	.NOTES
		Date: July 2026
#>
function Write-Log {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true, Position=0)]
		[ValidateSet("CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG")]
		[string] $Level,

		[Parameter(Mandatory=$true, Position=1)]
		[string]$Message
	)

	# Check if we should log this level
	if ($LogValues[$Level] -lt $LogValues[$LogLevel]) {
		return
	}

	# Gather metadata
	$timestamp = Get-Date -Format $TimestampFormat
	$callInfo = "$($PID):$([System.Threading.Thread]::CurrentThread.ManagedThreadId)"

	# Write message
	Write-Color "[{{Cyan:$($timestamp)}}] [{{Cyan:$($callInfo)}}] [{{$($LogColors[$Level]):$($levelName)}}] $($Message)"
}

# ============================================================================
# CONCURRENCY
# ============================================================================
# ================ Declarations
set-Variable -Name sync -Scope Script -Visibility Private

<#
	.SYNOPSIS
	.DESCRIPTION
	.PARAMETER None
	.EXAMPLE
	.INPUTS
	.OUTPUTS
		System.Void
	.COMPONENT
		Concurrency
	.LINK
	.NOTES
		Date: July 2026
#>
function Initialize-Concurrency {
	[CmdletBinding()]
	[OutputType([System.Void])]
	param()
	process {
		if ($sync.runspace -and $sync.runspace.RunspacePoolStateInfo.State -eq [System.Management.Automation.Runspaces.RunspacePoolState]::Opened) {
			return $sync.runspace
		}

		if ($sync.runspace) {
			Close-Concurrency
		}

		# Create a new session state for parsing variables into the runspace
		# $hashVars = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $sync, $null
		# $offlineVar = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'PARAM_OFFLINE', $PARAM_OFFLINE, $null
		# $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

		# $initialSessionState.Variables.Add($hashVars)
		# $initialSessionState.Variables.Add($offlineVar)

		# Insert functions into the session state
		# $functionList = @(
		# 	"Write-Color",
		# 	"Write-Log"
		# )
		# $functions = Get-ChildItem function:\ | Where-Object { $_.Name -in $functionList }
		# foreach ($function in $functions) {
		# 	$functionDefinition = Get-Content function:\$($function.Name)
		# 	$functionEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $function.Name, $functionDefinition
		# 	$initialSessionState.Commands.Add($functionEntry)
		# }

		$sync.runspace = [runspacefactory]::CreateRunspacePool(
			1,						# Minimum thread count
			$MaxThreads,			# Maximum thread count
			#$initialSessionState,	# Initial session state
			$Host					# Machine to create runspaces on
		)

		$sync.runspace.Open()
		return $sync.runspace
	}
}

<#
	.SYNOPSIS
	.DESCRIPTION
	.PARAMETER None
	.EXAMPLE
	.INPUTS
	.OUTPUTS
		System.Void
	.COMPONENT
		Concurrency
	.LINK
	.NOTES
		Date: July 2026
#>
function Close-Concurrency {
	[CmdletBinding()]
	[OutputType([System.Void])]
	param()
	process {
		if ($null -eq $sync -or -not $sync.ContainsKey("runspace") -or $null -eq $sync.runspace) {
			return
		}

		$states = @(
			[System.Management.Automation.Runspaces.RunspacePoolState]::Closed,
			[System.Management.Automation.Runspaces.RunspacePoolState]::Closing,
			[System.Management.Automation.Runspaces.RunspacePoolState]::Broken
		)

		try {
			if ($sync.runspace.RunspacePoolStateInfo.State -notin $states) {
				$sync.runspace.Close()
			}
		} finally {
			$sync.runspace.Dispose()
			$sync.Remove("runspace")
		}

		Write-Log "" ""
	}
}







Set-Variable -Name workerCount -Scope Script -Visibility Private
Set-Variable -Name semaphore -Scope Script -Visibility Private
Set-Variable -Name results -Scope Script -Visibility Private
Set-Variable -Name timerPS -Scope Script -Visibility Private
# Number of workers to dispatch
$workerCount = $Rate * $Period # Rate per second by time period in seconds
# Global Semaphore
$semaphore = [System.Threading.SemaphoreSlim]::new(0, $Rate)
# Thread-Safe Collection for results
$results = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()
# Timer Thread
$timerPS = [powershell]::Create().AddScript({
	param($s, $r)
	while ($true) {
		$needed = $r - $s.CurrentCount
		if ($needed -gt 0) { [void]$s.Release($needed) }
		Start-Sleep -Seconds 1
	}
}).AddArgument($semaphore).AddArgument($Rate)
$timerPS.RunspacePool = $runspacePool

$timerHandle = $timerPS.BeginInvoke()

# Dispatch Worker Threads
$tasks = [System.Collections.Generic.List[psobject]]::new()

Write-Log "INFO" "Dispatching $workerCount workers into the pool"
foreach ($reqId in 1..$workerCount) {
	$workerPS = [powershell]::Create().AddScript({
		param($id, $sem)
		
		# Block until a token is available
		$sem.Wait()
		
		# --- WEB APPLICATION TEST LOGIC GOES HERE ---
		# Example: Invoke-WebRequest -Uri "https://target..."
		
		# Return an object representing the result
		[pscustomobject]@{
			RequestID = $id
			ThreadID  = [System.Threading.Thread]::CurrentThread.ManagedThreadId
			Timestamp = Get-Date -Format $TimestampFormat
		}
	}).AddArgument($reqId).AddArgument($semaphore)
	
	$workerPS.RunspacePool = $runspacePool
	
	# Store the PS instance and its async handle so we can track it
	$tasks.Add([pscustomobject]@{
		PowerShellInstance = $workerPS
		AsyncResult        = $workerPS.BeginInvoke()
	})
}

# 5. Monitor and Collect Results
Write-Host "Waiting for tasks to complete..."
while ($tasks.AsyncResult.IsCompleted -contains $false) {
	Start-Sleep -Milliseconds 100
}

foreach ($task in $tasks) {
	# EndInvoke blocks until the specific thread finishes, then grabs the output stream
	$output = $task.PowerShellInstance.EndInvoke($task.AsyncResult)
	if ($output) { $results.Add($output) }
	
	# CRITICAL: Dispose of the individual PowerShell instance
	$task.PowerShellInstance.Dispose()
}

# 6. Cleanup & Teardown
$timerPS.Stop()       # Force kill the infinite timer loop
$timerPS.Dispose()
$runspacePool.Close()
$runspacePool.Dispose()
$semaphore.Dispose()

# Display sorted results
$results | Sort-Object RequestID | Format-Table -AutoSize

# ============================================================================
# HTTP
# ============================================================================

<#
	.SYNOPSIS
		Detect proxy authentication method
	.DESCRIPTION
		...
	.PARAMETER ...
		...
	.EXAMPLE
		...
	.INPUTS
		...
	.OUTPUTS
		...
	.COMPONENT
		...
	.LINK
		...
	.NOTES
		...
#>
function Get-ProxyAuthMethod {
	param(
		[Parameter(Mandatory)]
		[System.Uri] $Url
	)
	process {
		Write-Log "DEBUG" "Detecting proxy authentication method for: $Url"
		
		# Make a test request without credentials to get auth challenge
		try {
			$null = Invoke-WebRequest -Uri "https://www.google.com/" -Method "GET" -Proxy $Url.AbsoluteUri -UseBasicParsing $true -TimeoutSec 7 -ErrorAction Stop
			Write-Log "DEBUG" "Proxy does not require authentication"
			return "None"
		} catch {
			# Check if the response code is Proxy Authentication Required
			if ([string]::IsNullOrEmpty($_.Exception.Response.StatusCode) -or $_.Exception.Response.StatusCode -ne 407) {
				Write-Log "ERROR" "Unable to detect proxy auth method: $($_.Exception.Message)"
				return "Unknown"
			}
	
			# Get the Proxy-Authenticate header
			$authHeader = $_.Exception.Response.Headers["Proxy-Authenticate"]
			
			if ([string]::IsNullOrEmpty($authHeader)){
				Write-Log "ERROR" "No Proxy-Authenticate header was found"
				return "Unknown"
			}
	
			$authMethods = @()
			foreach ($header in $authHeader) {
				if ($header -match "^(\w+)") {
					$authMethods += $matches[1]
				}
			}
			
			Write-Log "DEBUG" "Proxy supports authentication methods: $($authMethods -join ", ")"
			
			# Prioritize: Negotiate > NTLM > Digest > Basic
			if ($authMethods -contains "Negotiate") {
				return "Negotiate"
			}
			
			if ($authMethods -contains "NTLM") {
				return "NTLM"
			}
			
			if ($authMethods -contains "Digest") {
				return "Digest"
			}
			
			if ($authMethods -contains "Basic") {
				return "Basic"
			}
			
			return $authMethods[0]
		}
	}
}

<#
	.SYNOPSIS
		Prepare proxy connection
	.DESCRIPTION
		...
	.PARAMETER ...
		...
	.EXAMPLE
		...
	.INPUTS
		...
	.OUTPUTS
		...
	.COMPONENT
		...
	.LINK
		...
	.NOTES
		...
#>
function Initialize-Proxy {
	param(
		[Parameter(Mandatory, Position = 0)]
		[System.Uri] $Url,

		[Parameter(Position = 1)]
		[string] $Username,

		[Parameter(Position = 2)]
		[string] $Password,

		[ValidateSet("Auto", "Basic", "NTLM", "Negotiate", "Digest", "DefaultCredentials", "None")]
		[string] $AuthMethod = "Auto"
	)
	process {
		$proxy = [System.Net.WebProxy]::new($Url.AbsoluteUri)
	
		# Detect authentication method if Auto
		$selectedAuthMethod = $AuthMethod
		if ($selectedAuthMethod -eq "Auto") {
			$selectedAuthMethod = Get-ProxyAuthMethod -Url $Url
		}
	
		Write-Log "DEBUG" "Proxy authentication method: $selectedAuthMethod"
	
		# Configure credentials
		$credentials = $null
	
		switch ($selectedAuthMethod) {
			"None" {
				Write-Log "WARNING" "No proxy authentication method configured"
			}
			"DefaultCredentials" {
				# Use current Windows credentials (works for NTLM/Negotiate)
				Write-Log "DEBUG" "Using default Windows credentials for proxy"
				$credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
			}
			"Unknown" {
				Write-Log "WARNING" "Unknown proxy authentication method, using default credentials"
				$credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
			}
			default {
				if (-not $Username) {
					$Username = Read-Host -Prompt "Enter username for proxy authentication"
				}
				if (-not $Password) {
					$Password = Read-Host -Prompt "Enter password for proxy authentication" -AsSecureString
				}
				$credentials = New-Object System.Management.Automation.PSCredential($Username, $Password)
			}
		}
	
		$proxy.Credentials = $credentials

		return $proxy
	}
}

# Http handler
$Handler = [System.Net.Http.SocketsHttpHandler]::new()
$Handler.PooledConnectionLifetime = [System.TimeSpan]::FromMinutes(5)


$Handler.Proxy = $Proxy
$Handler.UseProxy = $true


# Cookie
$Cookies = [System.Net.CookieContainer]::new()
$Handler.CookieContainer = $Cookies
$Handler.UseCookies = $true

$Cookies.Add(
    [System.Uri]"uri",
    [System.Net.Cookie]::new("PHPSESSION", "abc123")
)


# Http Client
$HttpClient = [System.Net.Http.HttpClient]::new($Handler)
$HttpClient.Timeout = [System.TimeSpan]::FromSeconds(10)


# Add default headers
$HttpClient.DefaultRequestHeaders.Add("Authorization", "Bearer YOUR_TOKEN")


# Create request and manage it
$Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get,$Url)
$Request.Headers.Add("Authorization", "Bearer YOUR_TOKEN")
$response = $HttpClient.SendAsync($Request).GetAwaiter().GetResult()


# Send request directly
$response = $HttpClient.GetAsync($Url).GetAwaiter().GetResult()



# ============================================================================
# END
# ============================================================================
Write-Color "{{Green:[*]}} Done in $([Math]::Truncate($stopwatch.Elapsed.TotalSeconds)).$($stopwatch.Elapsed.Milliseconds) seconds"

if ($Error.Count -gt 0) {
	Write-Color "{{Red:[!] Error Stack}}: The execution throwed $($Error.Count) omitted errors:"
	$Error | Select-Object -Property @{N='Error Message'; E={$_.Exception.Message}}, CategoryInfo, InvocationInfo | Format-Table -Wrap
}