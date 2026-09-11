<#
.SYNOPSIS
    Drive the three-node RHCSA/RHCE lab from Windows.

.DESCRIPTION
    A thin wrapper over vagrant so the everyday lab actions are one word each,
    and so snapshots — the habit the whole break-fix half of the curriculum
    depends on — are impossible to get wrong.

.EXAMPLE
    .\lab.ps1 up
    .\lab.ps1 snap clean
    .\lab.ps1 check 2.5 rhel01
    .\lab.ps1 restore clean
    .\lab.ps1 break-advanced random
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'status', 'ssh', 'halt', 'destroy', 'reload', 'provision',
                 'snap', 'restore', 'snaps', 'check', 'break', 'break-advanced',
                 'reveal', 'doctor', 'help',
                 'incident', 'objective', 'sla', 'grade', 'abandon')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest,

    # exam conditions: no diagnostics on failure, warnings count as failures,
    # tighter tolerances, and a pass requires proof it survived a reboot
    [switch]$Hard,
    [switch]$Blind
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$Nodes = @('rhel-control', 'rhel01', 'rhel02')
# The blank lab disks are created and attached by the Vagrantfile itself, not
# by `config.vm.disk`, because Vagrant's disk reconciliation cannot survive a
# `vagrant snapshot restore` — see section 4 of 00-Lab-Environment. So
# VAGRANT_EXPERIMENTAL is no longer needed, and is left unset deliberately.

function Invoke-Vagrant { & vagrant @args; if ($LASTEXITCODE -ne 0) { throw "vagrant $($args -join ' ') failed ($LASTEXITCODE)" } }
function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Ok($m)   { Write-Host $m -ForegroundColor Green }

function Show-Help {
    @"
lab.ps1 — the three-node RHCSA/RHCE lab on Vagrant + VirtualBox

  up                       build or start all three nodes
  status                   what is running
  ssh   [node]             shell on a node (default rhel01)
  halt                     shut all three down
  reload                   restart, re-reading the Vagrantfile
  provision                re-run provisioning without rebuilding
  destroy                  delete the VMs (keeps the box and your keys)

  snap    <name> [node]    snapshot all three, or one node
  restore <name> [node]    roll back to a snapshot
  snaps                    list snapshots

  check <lab> [node]       run a lab checker inside a node
                             lab.ps1 check 2.5 rhel01
                             lab.ps1 check env rhel-control
  break <fault> [node]     inject a single-cause fault  (default rhel01)
  break-advanced <f|random> [node]
                           inject one of the ten harder faults
  reveal [node]            what the advanced saboteur did, and how long you took

  incident <1-4> [node]    open an INCIDENT: several faults at once, a work order,
                           and a clock. Level 4 fights back.
  objective [node]         re-print the work order
  sla [node]               how long the incident has been open
  grade [node]             grade the incident (add -Hard for exam conditions)
  abandon [node]           surrender: stop the persistence, then reveal

  doctor                   check the host is fit to run the lab

The first `up` downloads a ~1 GB box, so it takes a while. After that a full
rebuild is a couple of minutes.

Before Week 1:   .\lab.ps1 up ; .\lab.ps1 check env rhel-control ; .\lab.ps1 snap clean

Incident drill:  .\lab.ps1 snap pre-incident
                 .\lab.ps1 incident 3
                 .\lab.ps1 objective        # what was reported
                 ... diagnose, repair, REBOOT ...
                 .\lab.ps1 grade            # or: grade -Hard
                 .\lab.ps1 reveal
"@
}

function Resolve-Node([string[]]$r, [int]$i = 0, [string]$default = 'rhel01') {
    if ($r -and $r.Count -gt $i -and $r[$i]) { return $r[$i] }
    return $default
}

switch ($Command) {

    'help' { Show-Help }

    'up' {
        Info "Building the lab. The first run downloads the box — be patient."
        Invoke-Vagrant up
        Ok "`nUp. Now: .\lab.ps1 check env rhel-control   then   .\lab.ps1 snap clean"
    }

    'status'    { Invoke-Vagrant status }
    'halt'      { Invoke-Vagrant halt }
    'reload'    { Invoke-Vagrant reload }
    'provision' { Invoke-Vagrant provision }

    'destroy' {
        Warn "This deletes all three VMs. Your Vagrantfile, keys and snapshots-on-disk go too."
        Invoke-Vagrant destroy -f
    }

    'ssh' { Invoke-Vagrant ssh (Resolve-Node $Rest) }

    'snap' {
        $name = Resolve-Node $Rest 0 ''
        if (-not $name) { throw "snapshot needs a name:  .\lab.ps1 snap clean" }
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { $null }
        if ($node) { Invoke-Vagrant snapshot save $node $name --force }
        else { foreach ($n in $Nodes) { Info "snapshot $n -> $name"; Invoke-Vagrant snapshot save $n $name --force } }
        Ok "Snapshot '$name' taken."
    }

    'restore' {
        $name = Resolve-Node $Rest 0 ''
        if (-not $name) { throw "restore needs a name:  .\lab.ps1 restore clean" }
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { $null }
        if ($node) { Invoke-Vagrant snapshot restore $node $name --no-provision }
        else { foreach ($n in $Nodes) { Info "restore $n <- $name"; Invoke-Vagrant snapshot restore $n $name --no-provision } }
        Ok "Restored '$name'."
    }

    'snaps' { foreach ($n in $Nodes) { Write-Host "`n${n}:" -ForegroundColor Cyan; & vagrant snapshot list $n } }

    'check' {
        $lab = Resolve-Node $Rest 0 ''
        if (-not $lab) { throw "which lab?  .\lab.ps1 check 2.5 rhel01" }
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { 'rhel01' }
        # 4.1 is the rootless-container lab: it must NOT run as root.
        $asRoot = ($lab -ne '4.1')
        $extra = ''
        if ($Hard)  { $extra += ' --hard' }
        if ($Blind) { $extra += ' --blind' }
        $inner = if ($asRoot) { "sudo /opt/rhce-labs/verify $lab$extra" } else { "/opt/rhce-labs/verify $lab$extra" }
        Info "$node : $inner"
        & vagrant ssh $node -c $inner
    }

    'break' {
        $fault = Resolve-Node $Rest 0 'random'
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { 'rhel01' }
        Warn "Snapshot first if you have not:  .\lab.ps1 snap pre-lab $node"
        & vagrant ssh $node -c "sudo /opt/rhce-labs/break/break.sh $fault"
    }

    'break-advanced' {
        $fault = Resolve-Node $Rest 0 'random'
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { 'rhel01' }
        Warn "These are the harder faults. Snapshot first:  .\lab.ps1 snap pre-lab $node"
        & vagrant ssh $node -c "sudo /opt/rhce-labs/break/break-advanced.sh $fault --yes"
    }

    'reveal' {
        $node = Resolve-Node $Rest
        & vagrant ssh $node -c "sudo /opt/rhce-labs/break/break-advanced.sh reveal"
    }

    'incident' {
        $lvl = Resolve-Node $Rest 0 '2'
        $node = if ($Rest.Count -gt 1) { $Rest[1] } else { 'rhel01' }
        Warn "Snapshot first — there is no undo:  .\lab.ps1 snap pre-incident"
        Info "Opening a severity-$lvl incident on $node"
        & vagrant ssh $node -c "sudo /opt/rhce-labs/break/incident.sh open $lvl --yes"
        Ok  "`nWork order:  .\lab.ps1 objective $node"
        Warn "Some of it only shows after a reboot. Reboot before you start."
    }

    'objective' { & vagrant ssh (Resolve-Node $Rest) -c "sudo /opt/rhce-labs/break/incident.sh objective" }
    'sla'       { & vagrant ssh (Resolve-Node $Rest) -c "sudo /opt/rhce-labs/break/incident.sh status" }
    'abandon'   { & vagrant ssh (Resolve-Node $Rest) -c "sudo /opt/rhce-labs/break/incident.sh abandon --yes" }

    'grade' {
        $node = Resolve-Node $Rest
        $flags = ''
        if ($Hard)  { $flags += ' --hard' }
        if ($Blind) { $flags += ' --blind' }
        Info "$node : verify incident$flags"
        & vagrant ssh $node -c "sudo /opt/rhce-labs/verify incident$flags"
    }

    'doctor' {
        Write-Host "`nHost readiness" -ForegroundColor Cyan

        $v = (& vagrant --version 2>&1 | Out-String).Trim()
        Write-Host ("  vagrant           : {0}" -f $v)

        $vbox = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
        if (Test-Path $vbox) {
            Write-Host ("  virtualbox        : {0}" -f (& $vbox --version 2>&1 | Out-String).Trim())
        } else { Warn "  virtualbox        : VBoxManage.exe not found" }

        $hostonly = if (Test-Path $vbox) { (& $vbox list hostonlyifs | Select-String 'IPAddress:' | Out-String).Trim() } else { '' }
        Write-Host ("  host-only net     : {0}" -f ($hostonly -replace '\s+', ' '))
        if ($hostonly -notmatch '192\.168\.56\.') {
            Warn "                      expected a 192.168.56.x adapter; VirtualBox only allows"
            Warn "                      192.168.56.0/21 unless %ProgramData%\VirtualBox\networks.conf says otherwise"
        }

        $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        Write-Host ("  host RAM          : {0} GB  (the lab wants ~5 GB free)" -f $ram)

        $free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
        Write-Host ("  free disk on C:   : {0} GB  (the box plus three linked clones: ~8 GB)" -f $free)

        if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
            Warn "  hypervisor        : ACTIVE (Hyper-V / WSL2 / Memory Integrity)"
            Warn "                      VirtualBox will run nested and noticeably slower."
            Warn "                      It works. To get full speed you would have to turn off"
            Warn "                      Core Isolation > Memory Integrity and hypervisorlaunchtype,"
            Warn "                      which also disables WSL2 and Docker Desktop — your call."
        } else {
            Ok   "  hypervisor        : none competing — VirtualBox gets the CPU directly"
        }

        if (Test-Path (Join-Path $PSScriptRoot 'keys\lab_ed25519')) {
            Ok "  lab ssh key       : present"
        } else {
            Write-Host "  lab ssh key       : will be created on first 'up'"
        }
        Write-Host ""
    }
}
