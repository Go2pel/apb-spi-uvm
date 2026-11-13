param([string]$VivadoBin)

$ErrorActionPreference = 'Stop'

if (-not $VivadoBin) {
    $VivadoBin = Split-Path -Parent (Get-Command xvlog.bat).Source
}

$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$project = Split-Path -Parent $PSScriptRoot
$build = Join-Path ([System.IO.Path]::GetTempPath()) ('apb-spi-uvm-' + [guid]::NewGuid().ToString('N'))
$sources = @(
    'rtl/spi_fifo.sv', 'rtl/spi_mode0_frame.sv', 'rtl/apb_spi.sv',
    'tb/apb_spi_assertions.sv', 'tb/apb_spi_smoke.sv'
)
$sourceNames = $sources | ForEach-Object { Split-Path -Leaf $_ }

New-Item -ItemType Directory -Path $build | Out-Null
foreach ($source in $sources) {
    Copy-Item -LiteralPath (Join-Path $project $source) -Destination $build
}

Write-Host "Build and logs: $build"
Push-Location -LiteralPath $build
try {
    & (Join-Path $VivadoBin 'xvlog.bat') -sv @sourceNames
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    & (Join-Path $VivadoBin 'xelab.bat') apb_spi_smoke -s apb_spi_smoke_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

    & (Join-Path $VivadoBin 'xsim.bat') apb_spi_smoke_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
    if (-not (Select-String -LiteralPath 'xsim.log' -Pattern '^PASS apb_spi_smoke\s*$' -Quiet)) {
        throw 'Smoke test did not print its final PASS marker. Check xsim.log.'
    }
} finally {
    Pop-Location
}
