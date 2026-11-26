#Requires -Version 5.1
param(
    [string]$ResultsDirectory = [IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
$classes = & (Join-Path $PSScriptRoot 'build-adage.ps1') -Unmodified
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../vendor/ADAGE')).Path
$classPath = $classes + [IO.Path]::PathSeparator + (Join-Path $source 'lib/*')
$upstreamCommit = git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere il commit ADAGE.' }
$javaVersion = java --version
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere la versione di Java.' }
$javacVersion = javac -version
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere la versione di javac.' }

$runName = 'adage-wp1-' + [guid]::NewGuid().ToString('N')
$run = New-Item -ItemType Directory -Path (Join-Path $ResultsDirectory $runName)
$results = Join-Path $run.FullName 'results.csv'
$nodes = 16
$bandwidth = 1000
$seed = 0
$scheduler = 'WORKGIVING'
$planner = 'CRITICAL_PATH'
$modes = -1, 0, 2
$workflows = 'config/dax/Montage_25.xml', 'config/dax/Montage_1000.xml'

$metadata = [ordered]@{
    started_utc = [DateTimeOffset]::UtcNow.ToString('o')
    upstream_commit = $upstreamCommit
    build = 'unmodified-source'
    java = $javaVersion -join [Environment]::NewLine
    javac = $javacVersion -join [Environment]::NewLine
    nodes = $nodes
    bw_cli = $bandwidth
    scheduler = $scheduler
    planner = $planner
    seed = $seed
    wg_modes = $modes
    workflows = @(
        foreach ($workflow in $workflows) {
            $hash = Get-FileHash -LiteralPath (Join-Path $source $workflow) -Algorithm SHA256
            @{ path = $workflow; sha256 = $hash.Hash.ToLowerInvariant() }
        }
    )
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run.FullName 'run.json') -Encoding UTF8
Write-Host "Risultati e log in $($run.FullName)"

foreach ($workflow in $workflows) {
    $dax = Join-Path $source $workflow
    $workflowName = [IO.Path]::GetFileNameWithoutExtension($dax)
    [xml]$daxXml = Get-Content -LiteralPath $dax -Raw
    $expectedCount = $daxXml.SelectNodes("/*[local-name()='adag']/*[local-name()='job']").Count
    if ($expectedCount -eq 0) { throw "Nessun task nel workflow $workflow." }

    foreach ($mode in $modes) {
        $logFolder = "$workflowName/mode-$mode"
        $logPath = Join-Path $run.FullName $logFolder
        $arguments = @(
            $dax, '--nodes', $nodes, '--bw', $bandwidth, '--sched', $scheduler,
            '--plan', $planner, '--wgmode', $mode, '--seed', $seed, '--log', $logPath
        )
        $output = java '-Duser.language=en' '-Duser.country=US' -cp $classPath simulation.Simulation @arguments
        if ($LASTEXITCODE -ne 0) { throw "Simulazione fallita per $workflowName, modalita $mode." }
        if ($output -isnot [string] -or $output -notmatch '^([0-9.eE+-]+);(\d+);(\d+)$') {
            throw "Output inatteso per $workflowName, modalita $mode."
        }
        $makespan = $Matches[1]
        $backupCount = [int]$Matches[2]
        $regularCount = [int]$Matches[3]

        $log = @(Get-ChildItem -LiteralPath $logPath -File -Filter '*.log')
        if ($log.Count -ne 1) { throw "Log inatteso in $logPath." }
        $completed = @(Get-Content -LiteralPath $log[0].FullName | ForEach-Object {
            if ($_ -match '^\s*\d+\s+\[(\d+)\]\s+Success\s') { [int]$Matches[1] }
        } | Sort-Object -Unique)
        if ($completed.Count -ne $expectedCount -or (Compare-Object (1..$expectedCount) $completed)) {
            throw "ID dei task completati inattesi per $workflowName, modalita $mode."
        }

        [pscustomobject][ordered]@{
            workflow = $workflowName
            wg_mode = $mode
            makespan_seconds = $makespan
            tasks_completed = $completed.Count
            tasks_expected = $expectedCount
            backup_counter = $backupCount
            non_backup_counter = $regularCount
            log = "$logFolder/$($log[0].Name)"
        } | Export-Csv -LiteralPath $results -NoTypeInformation -Encoding UTF8 -Append
    }
}

Import-Csv -LiteralPath $results | Format-Table workflow, wg_mode, makespan_seconds, tasks_completed
