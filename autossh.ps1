<#
.SYNOPSIS
  Powershell script for keeping ssh tunnel up and running

.DESCRIPTION
  This script uses configuration of tunnels located in config.csv. For more information visit (deadlink) http://tsherlock.tech/2019/03/13/simple-ssh-tunnel-auto-reconnect-using-putty-and-powershell/

.NOTES
  Version:        1.0.1
  Author:         Anton Shkuratov
  Creation Date:  2019-03-13
  Purpose/Change: Initial script development
  Author:         Gerald Urbas
  Update Date:    2021-03-05
  Purpose/Change: Regexp Fixed in code that i found in a Stack comment / aboce Info link is dead
#>

$currentDir = $PSScriptRoot
if (-not $env:PATH.Contains($currentDir)) {
  $env:PATH="$env:PATH;$currentDir"
}

# Check plink is accessible
try {
  Start-Process plink.exe -WindowStyle Hidden
} catch {
  Write-Host Error running plink.exe Please make sure its path is in PATH environment variable
  EXIT 1
}

# Parse config
$config = [System.IO.File]::ReadAllLines("$currentDir\config.csv");
$bindings = New-Object System.Collections.ArrayList
$regex = New-Object System.Text.RegularExpressions.Regex("(\d+)+\s([^ ]+)\s(\d+)\s([^ ]+)\s([^ ]+)\s([^ ]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase);
$keyPasswords = @{}
$procs = @{}

foreach($line in $config) {
  $match = $regex.Match($line)

  if ($match.Success) {
    $sshKey = $match.Groups[6];

    $bindings.Add(@{
      LocalPort = $match.Groups[1];
      TargetHost = $match.Groups[2];
      TargetPort = $match.Groups.Groups[3];
      SshHost = $match.Groups[4];
      SshUser = $match.Groups[5];
      SshKey = $match.Groups[6];
    });

    if (-not $keyPasswords.ContainsKey($sshKey)) {
      $pass = Read-Host "Please enter password for key (if set): $sshKey" -AsSecureString
      $keyPasswords.Add($sshKey, $pass);
    }
  }
}

# Starting Processes
function EnsureRunning($procs, $keyPasswords, $binding) {

  if ($procs.ContainsKey($binding) -and $procs[$binding].HasExited) {

    $proc = $procs[$binding]
    $sshKey = $binding.sshKey
    $out = $proc.StandardError.ReadToEnd()

    if ($out.Contains("Wrong passphrase")) {
      Write-Host "Wrong pass phrase for $sshKey, please re-enter"
      $pass = Read-Host "Please enter password for key: $sshKey" -AsSecureString
      $keyPasswords[$sshKey] = $pass;
    } else {
      $exitCode = $proc.ExitCode
      $tHost = $binding.sshHost

      Write-Host "Connection to $tHost is lost, exit code: $exitCode"
    }
  }

  if (-not $procs.ContainsKey($binding) -or $procs[$binding].HasExited) {
    $sshUser = $binding.SshUser
    $sshHost = $binding.SshHost
    $sshKey = $binding.SshKey
    $lPort = $binding.LocalPort
    $tPort = $binding.TargetPort
    $tHost = $binding.TargetHost
    $sshKeyPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPasswords[$sshKey]))

    $psi = New-Object System.Diagnostics.ProcessStartInfo;
    $psi.FileName = "plink.exe";
    $psi.UseShellExecute = $false;

    $psi.CreateNoWindow = $true;
    $psi.RedirectStandardInput = $true;
    $psi.RedirectStandardError = $true;
	<# Write-Host "-ssh $sshUser@$sshHost -i `"$sshKey`" -batch -pw $sshKeyPass -L $lPort`:$tHost`:$tPort"
	#>
    $psi.Arguments = "-ssh $sshUser@$sshHost -i `"$sshKey`" -batch -L $lPort`:$tHost`:$tPort"

    $proc = [System.Diagnostics.Process]::Start($psi);

    Start-Sleep 1

    if (-not $proc.HasExited) {
      Write-Host Connected to $sshUser@$sshHost Port $lPort for $tHost Port $tPort
    }

    $procs[$binding] = $proc;
  }
}

function EnsureAllRunning($procs, $keyPasswords, $bindings) {
  while($true) {
    foreach($binding in $bindings) {
      EnsureRunning $procs $keyPasswords $binding
    }
    Start-Sleep 1
  }
}


try {
  # Waiting for exit command
  Write-Host Working... Press Ctrl+C to stop execution...
  EnsureAllRunning $procs $keyPasswords $bindings
} finally {
  # Clean up
  Write-Host Clean up

  foreach($proc in $procs.Values) {
    if ($proc -ne $null -and -not $proc.HasExited) {
      $proc.Kill();
    }
  }
}
