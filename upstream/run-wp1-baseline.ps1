#Requires -Version 5.1
param(
    [string]$ResultsDirectory = [IO.Path]::GetTempPath(),
    [string]$JavaHome,
    [switch]$StablePlanner
)

$ErrorActionPreference = 'Stop'

function Get-Wp1FileSha256([string]$Path) {
    $hash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Impossibile calcolare SHA-256 per il file: $Path"
    }
    $hash.ToLowerInvariant()
}

if ($JavaHome) {
    $JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
    $suffix = if ([Environment]::OSVersion.Platform -eq 'Win32NT') { '.exe' } else { '' }
    $java = (Resolve-Path -LiteralPath (Join-Path $JavaHome "bin/java$suffix")).Path
    $javac = (Resolve-Path -LiteralPath (Join-Path $JavaHome "bin/javac$suffix")).Path
} else {
    $java = (Get-Command java -CommandType Application | Select-Object -First 1).Source
    $javac = (Get-Command javac -CommandType Application | Select-Object -First 1).Source
}

$classes = & (Join-Path $PSScriptRoot 'build-adage.ps1') -Unmodified -JavaHome $JavaHome
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../vendor/ADAGE')).Path
$classPath = $classes + [IO.Path]::PathSeparator + (Join-Path $source 'lib/*')
$buildVariant = 'unmodified-source'
$plannerPatchHash = $null
if ($StablePlanner) {
    $buildDirectory = Split-Path -Parent $classes
    $relativeSource = 'src/org/workflowsim/planning/CriticalPathPlanningAlgorithm.java'
    $plannerSource = Join-Path $buildDirectory $relativeSource
    New-Item -ItemType Directory -Path (Split-Path -Parent $plannerSource) | Out-Null
    $sourceText = [IO.File]::ReadAllText((Join-Path $source $relativeSource))
    [IO.File]::WriteAllText($plannerSource, ($sourceText -replace '\r\n', [string][char]10), [Text.UTF8Encoding]::new($false))

    $plannerPatch = Join-Path $PSScriptRoot '0002-stable-planner-ties.patch'
    git -C $buildDirectory apply --unidiff-zero $plannerPatch
    if ($LASTEXITCODE -ne 0) { throw 'Impossibile applicare la patch del pianificatore.' }
    & $javac --release 11 -encoding UTF-8 -sourcepath $classes -cp $classPath -d $classes $plannerSource
    if ($LASTEXITCODE -ne 0) { throw 'Compilazione del pianificatore fallita.' }

    $buildVariant = 'stable-planner'
    $plannerPatchHash = Get-Wp1FileSha256 $plannerPatch
}
$upstreamCommit = git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere il commit ADAGE.' }
$runnerCommit = git -C $PSScriptRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere il commit del runner WP1.' }
$javaVersion = & $java --version
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere la versione di Java.' }
$javacVersion = & $javac -version
if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere la versione di javac.' }

$runName = 'adage-wp1-' + [guid]::NewGuid().ToString('N')
$run = New-Item -ItemType Directory -Path (Join-Path $ResultsDirectory $runName)
$results = Join-Path $run.FullName 'results.csv'
$classManifest = Join-Path $run.FullName 'classes.sha256'
$classEntries = [string[]]@(Get-ChildItem -LiteralPath $classes -Recurse -File -Filter '*.class' | ForEach-Object {
    $relativePath = $_.FullName.Substring($classes.Length + 1).Replace('\', '/')
    $hash = Get-Wp1FileSha256 $_.FullName
    "$hash  $relativePath"
})
[Array]::Sort($classEntries, [StringComparer]::Ordinal)
[IO.File]::WriteAllText($classManifest, ($classEntries -join [char]10), [Text.UTF8Encoding]::new($false))
$jvmArguments = '-Duser.language=en', '-Duser.country=US'
$nodes = 16
$bandwidth = 1000
$seed = 0
$scheduler = 'WORKGIVING'
$planner = 'CRITICAL_PATH'
$modes = -1, 0, 2
$workflows = 'config/dax/Montage_25.xml', 'config/dax/Montage_1000.xml'

$javaOverrides = @(
    foreach ($optionName in 'JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVAC_OPTIONS') {
        if ([Environment]::GetEnvironmentVariable($optionName)) { $optionName }
    }
)
$osArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
if (-not $osArchitecture) {
    $osArchitecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $osArchitecture) { $osArchitecture = $env:PROCESSOR_ARCHITECTURE }
    if ($osArchitecture -eq 'AMD64') { $osArchitecture = 'X64' }
    if (-not $osArchitecture) { $osArchitecture = 'unknown' }
}

$metadata = [ordered]@{
    started_utc = [DateTimeOffset]::UtcNow.ToString('o')
    runner_commit = $runnerCommit
    runner_sha256 = Get-Wp1FileSha256 $PSCommandPath
    build_script_sha256 = Get-Wp1FileSha256 (Join-Path $PSScriptRoot 'build-adage.ps1')
    upstream_commit = $upstreamCommit
    build = $buildVariant
    planner_patch_sha256 = $plannerPatchHash
    class_manifest_sha256 = Get-Wp1FileSha256 $classManifest
    java = $javaVersion -join [Environment]::NewLine
    javac = $javacVersion -join [Environment]::NewLine
    java_executable = $java
    javac_executable = $javac
    java_executable_sha256 = Get-Wp1FileSha256 $java
    javac_executable_sha256 = Get-Wp1FileSha256 $javac
    jvm_arguments = $jvmArguments
    java_override_variables_set = $javaOverrides
    os = [Environment]::OSVersion.VersionString
    os_architecture = $osArchitecture
    logical_processors = [Environment]::ProcessorCount
    powershell = [string]$PSVersionTable.PSVersion
    jars = @(
        Get-ChildItem -LiteralPath (Join-Path $source 'lib') -File -Filter '*.jar' | Sort-Object Name | ForEach-Object {
            $hash = Get-Wp1FileSha256 $_.FullName
            @{ name = $_.Name; sha256 = $hash }
        }
    )
    nodes = $nodes
    bw_cli = $bandwidth
    scheduler = $scheduler
    planner = $planner
    seed = $seed
    wg_modes = $modes
    workflows = @(
        foreach ($workflow in $workflows) {
            $hash = Get-Wp1FileSha256 (Join-Path $source $workflow)
            @{ path = $workflow; sha256 = $hash }
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
        $output = & $java @jvmArguments -cp $classPath simulation.Simulation @arguments
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
