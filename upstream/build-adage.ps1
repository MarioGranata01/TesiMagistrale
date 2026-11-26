#Requires -Version 5.1
param(
    [string]$SourceDirectory = (Join-Path $PSScriptRoot '../vendor/ADAGE'),
    [switch]$Unmodified,
    [string]$JavaHome
)

$ErrorActionPreference = 'Stop'
$javac = 'javac'
if ($JavaHome) {
    $suffix = if ([Environment]::OSVersion.Platform -eq 'Win32NT') { '.exe' } else { '' }
    $javac = (Resolve-Path -LiteralPath (Join-Path $JavaHome "bin/javac$suffix")).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory 'simulation/simulation/Simulation.java') -PathType Leaf)) {
    throw 'Sorgente ADAGE assente. Inizializza il sottomodulo con git submodule update --init.'
}
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$expectedCommit = '063fa27d0eb0f90d123f917d7c51fd76eb153476'
$commit = git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $commit -ne $expectedCommit) {
    throw "Il checkout ADAGE deve puntare al commit $expectedCommit."
}

$changes = git -C $source status --porcelain --untracked-files=no
if ($LASTEXITCODE -ne 0 -or $changes) {
    throw 'Usa un checkout ADAGE con i file tracciati puliti.'
}

$build = Join-Path ([IO.Path]::GetTempPath()) ('a2dage-build-' + [guid]::NewGuid().ToString('N'))
$simulation = New-Item -ItemType Directory -Path (Join-Path $build 'simulation')
$classes = New-Item -ItemType Directory -Path (Join-Path $build 'classes')
Copy-Item -LiteralPath (Join-Path $source 'simulation/simulation') -Destination $simulation.FullName -Recurse

if (-not $Unmodified) {
    $patch = Join-Path $PSScriptRoot '0001-respect-simulation-seed.patch'
    git -C $build apply --unidiff-zero $patch
    if ($LASTEXITCODE -ne 0) {
        throw 'Impossibile applicare la patch ADAGE.'
    }
}

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $source 'src'), $simulation.FullName -File -Recurse -Filter '*.java'
$sourceList = Join-Path $build 'sources.txt'
$sourceArguments = $sourceFiles.FullName | ForEach-Object {
    '"' + $_.Replace('\', '/') + '"'
}
[IO.File]::WriteAllLines($sourceList, [string[]]$sourceArguments, [Text.UTF8Encoding]::new($false))

# Alcuni JAR contengono anche sorgenti. Il sourcepath isolato usa solo le loro classi.
& $javac --release 11 -encoding UTF-8 -sourcepath $classes.FullName -cp (Join-Path $source 'lib/*') -d $classes.FullName "@$sourceList"
if ($LASTEXITCODE -ne 0) {
    throw 'Compilazione ADAGE fallita.'
}

$classes.FullName
