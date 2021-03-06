using namespace System.Collections.Generic

Set-StrictMode -Version Latest

if (-not (Test-Path variable:PSSTAN_PATH)) {
    $global:PSSTAN_PATH = "C:\cmdstan"
}

if (-not (Test-Path variable:PSSTAN_TOOLS_PATHS)) {
    $global:PSSTAN_TOOLS_PATHS = @(
        "C:\RTools\bin",
        "C:\Rtools\mingw_64\bin"
    )
}

function New-StanExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Path,
        [Parameter(Position = 1, Mandatory = $false)]
        [string]$MakeOptions
    )

    $Path = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $Path = $Path -Replace "\.stan$", ".exe"
    $Path = $Path -Replace "\\", "/"
    $oldPath = $env:Path
    try {
        $env:Path = $global:PSSTAN_TOOLS_PATHS -join ";"
        Push-Location $global:PSSTAN_PATH
        Invoke-Expression "make $Path $MakeOptions"
    }
    finally {
        Pop-Location
        $env:Path = $oldPath
    }
}

function script:Invoke-StanSummary {
    param(
        [Dictionary[string, object]]$BoundParameters
    )

    $path = Resolve-Path $BoundParameters["Path"]

    $options = New-Object List[string]
    if ($BoundParameters.ContainsKey("SigFig")) {
        $options.Add("--sig_figs=$($BoundParameters["SigFig"])")
    }

    if ($BoundParameters.ContainsKey("Autocorr")) {
        $options.Add("--autocorr=$($BoundParameters["Autocorr"])")
    }

    if ($BoundParameters.ContainsKey("CsvFile")) {
        $options.Add("--csv_file='$($BoundParameters["CsvFile"])'")
    }

    $oldPath = $env:Path
    try {
        $env:Path = $global:PSSTAN_TOOLS_PATHS -join ";"
        $commandLine = "$global:PSSTAN_PATH\bin\stansummary '$Path' $($options -join " ")"
        Write-Verbose $commandLine
        Invoke-Expression $commandLine
    }
    finally {
        $env:Path = $oldPath
    }
}

function script:Strip-Output {
    param(
        [string]$InFIle,
        [string]$OutFile,
        [int]$Chain,
        [bool]$Append
    )

    $f = New-Object IO.StreamWriter $OutFile, $Append
    try {
        $headerAdded = $Append

        $sample = 1
        foreach ($line in (Get-Content $InFile)) {
            if ($line[0] -eq "#") {
                continue
            }
            if ($line -Match "^lp__,") {
                if ($HeaderAdded) {
                    continue
                }
                $HeaderAdded = $true
                $f.Write("chain__,sample__,")
                $f.WriteLine($Line)
            }
            else {
                $f.Write([string]$Chain + "," + [string]$sample + ",")
                $f.WriteLine($Line)
                ++$sample
            }
        }
    }
    finally {
        $f.Close()
    }
}

function Start-StanSampling {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$ModelFile,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$DataFile,
        [Parameter(Position = 2, Mandatory = $false)]
        [int]$ChainCount = 1,
        [Parameter(Position = 3, Mandatory = $false)]
        [string]$OutputFile = "output{0}.csv",
        [Parameter(Position = 4, Mandatory = $false)]
        [string]$CombinedFile = "combined.csv",
        [Parameter(Position = 5, Mandatory = $false)]
        [string]$ConsoleFile = $null,
        [Parameter(Position = 6, Mandatory = $false)]
        [switch]$Parallel,
        [Parameter(Position = 7, Mandatory = $false)]
        [int]$NumSamples = 1000,
        [Parameter(Position = 8, Mandatory = $false)]
        [int]$NumWarmup = 1000,
        [Parameter(Position = 9, Mandatory = $false)]
        [bool]$SaveWarmup = $false,
        [Parameter(Position = 10, Mandatory = $false)]
        [int]$Thin = 1,
        [Parameter(Position = 11, Mandatory = $false)]
        [int]$RandomSeed = 1234,
        [Parameter(Position = 12, Mandatory = $false)]
        [string]$Option = ""
    )

    if ($OutputFile.IndexOf("{0}") -eq -1) {
        Write-Error "The -OutputFile parameter should contain '{0}' as the placeholder of the chain count"
        exit
    }

    if (-not [string]::IsNullOrEmpty($ConsoleFile) -and $ConsoleFile.IndexOf("{0}") -eq -1) {
        Write-Error "The -ConsoleFile parameter should contain '{0}' as the placeholder of the chain count"
        exit
    }

    $ModelFile = Resolve-Path $ModelFile
    $DataFile = Resolve-Path $DataFile
    $OutputFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
    $CombinedFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CombinedFile)
    if (-not [string]::IsNullOrEmpty($ConsoleFile)) {
        $ConsoleFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConsoleFile)
    }

    if ($ModelFile.EndsWith(".exe")) {
        $executable = $ModelFile
    }
    else {
        Write-Output "***** Compiling model file"
        New-StanExecutable $ModelFile
        $executable = $ModelFile -replace "\.[^.]+$", ".exe"
    }

    Write-Output "***** Starting sampling"

    $commandLine = "$executable sample num_samples=$NumSamples num_warmup=$NumWarmup save_warmup=$([int]$SaveWarmup) thin=$Thin data file='$DataFile' random seed=$RandomSeed output file='$OutputFile' id={1} $Option"

    $stripped = "_stripped"
    $exitCodes = @()
    $exitMessage = "***** Chain {0} of {1} completed with exit code {2}"

    if ($Parallel -and $ChainCount -gt 1) {
        $tasks = @()

        try {
            for ($chain = 2; $chain -le $ChainCount; ++$chain) {
                $c = $commandLine -f $chain, $chain
                if ([string]::IsNullOrEmpty($ConsoleFile)) {
                    $c += ">`$null; `$LastExitCode"
                }
                else {
                    $c += " > $($ConsoleFile -f $chain); `$LastExitCode"
                }
                Write-Verbose $c

                $ps = [PowerShell]::Create("NewRunspace").AddScript($c)

                $tasks += @{
                    Chain = $chain
                    PowerShell = $ps
                    Result = $ps.BeginInvoke()
                }
            }

            $c = $commandLine -f 1, 1
            Write-Verbose $c
            if (-not [string]::IsNullOrEmpty($ConsoleFile)) {
                Invoke-Expression $c | Tee-Object -LiteralPath ($ConsoleFile -f 1)
            }
            else {
                Invoke-Expression $c
            }
            $exitCodes = @($LastExitCode)

            Write-Output ($exitMessage -f 1, $ChainCount, $LastExitCode)
        }
        finally {
            foreach ($t in $tasks) {
                $exitCode = $t["PowerShell"].EndInvoke($t["Result"])[0]
                $exitCodes += $exitCode
                $t["PowerShell"].Dispose()
                Write-Output ($exitMessage -f $t["Chain"], $ChainCount, $exitCode)
            }
        }

        for ($chain = 1; $chain -le $ChainCount; ++$chain) {
            Strip-Output ($OutputFile -f $chain) ($OutputFile -f "$stripped$chain") $chain
        }
    }
    else {
        for ($chain = 1; $chain -le $ChainCount; ++$chain) {
            $c = $commandLine -f $chain, $chain
            Write-Verbose $c
            Invoke-Expression $c
            $exitCodes += $LastExitCode
            Strip-Output ($OutputFile -f $chain) ($OutputFile -f "$stripped$chain") $chain
        }
    }

    Get-Content ($OutputFile -f "$($stripped)1") -Total 1 | Set-Content $CombinedFile
    for ($chain = 1; $chain -le $ChainCount; ++$chain) {
        Get-Content ($OutputFile -f "$stripped$chain") | Select-Object -Skip 1 | Add-Content $CombinedFile
    }

    if ($exitCodes -ne 0) {
        Write-Error "There are sampling chains that exited with non-zero exit codes; Consult console output files ($($exitCodes -join ", "))"
    }
}

function Show-StanSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$SigFig = 2,

        [Parameter(Position = 2, Mandatory = $false)]
        [int]$Autocorr,

        [Parameter(Position = 3, Mandatory = $false)]
        [string]$CsvFile
    )

    Invoke-StanSummary $PSBoundParameters
}

function Get-StanSummary {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$Autocorr,

        [Parameter(Position = 2, Mandatory = $false)]
        [string]$CsvFile
    )

    if (-not $PSBoundParameters.ContainsKey("CsvFile")) {
        $CsvFile = [IO.Path]::GetTempFileName()
        $PSBoundParameters.Add("CsvFile", $CsvFile)
    }
    else {
        If (Test-Path $CsvFile) {
            Remove-Item $CsvFile
        }
    }

    $null = Invoke-StanSummary $PSBoundParameters

    $parameters = Get-Content $CsvFile |
        Where-Object { $_ -NotMatch "^#" } |
        ConvertFrom-Csv

    $result = New-Object PSObject
    foreach ($p in $parameters) {
        Add-Member -InputObject $result -Type NoteProperty -Name $p.name -Value $p
    }

    $result
}

class StanData {
    [string]$Name

    StanData([string]$name) {
        $this.Name = $name
    }

    [string] ToString() {
        $builder = New-Object Text.StringBuilder
        $builder.Append($this.Name)
        $builder.Append(" <- ")

        $this.SerializeValue($builder)

        return $builder.ToString()
    }
}

class StanSequenceData : StanData {
    StanSequenceData([string]$name) : base ($name) {}
}

class StanArrayData : StanSequenceData {
    [double[]]$Values

    StanArrayData([string]$name, [double[]]$values) : base($name) {
        $this.Values = $values
    }

    [void] SerializeValue([Text.StringBuilder]$builder) {
        if ($this.Values.Length -eq 1) {
            $builder.Append($this.Values[0])
        }
        else {
            $builder.Append("c(")
            $builder.Append(($this.Values -join ", "))
            $builder.Append(")")
        }
    }
}

class StanZeroData : StanSequenceData {
    [string]$Type
    [int]$Count

    StanZeroData([string]$name, [string]$type, [int]$count) : base($name) {
        $this.Type = $type
        $this.Count = $count
    }

    [void] SerializeValue([Text.StringBuilder]$builder) {
        $builder.Append($this.Type)
        $builder.Append("(")
        $builder.Append($this.Count)
        $builder.Append(")")
    }
}

class StanRangeData : StanSequenceData {
    [double]$First
    [double]$Last

    StanRangeData([string]$name, [double]$first, [double]$last) : base($name) {
        $this.First = $first
        $this.Last = $last
    }

    [void] SerializeValue([Text.StringBuilder]$builder) {
        $builder.Append($this.First)
        $builder.Append(":")
        $builder.Append($this.Last)
    }
}

class StanStructureData : StanData {
    [StanSequenceData]$Data
    [int[]]$Dimensions

    StanStructureData([StanSequenceData]$data, [int[]]$dimensions) : base($data.Name) {
        $this.Data = $data
        $this.Dimensions = $dimensions
    }

    [void] SerializeValue([Text.StringBuilder]$builder) {
        $builder.Append("structure(")
        $this.Data.SerializeValue($builder)
        $builder.Append(", .Dim = c(")
        $builder.Append(($this.Dimensions -join ", "))
        $builder.Append("))")
    }
}

function New-StanData {
    [CmdletBinding(DefaultParameterSetName = "ArrayValue")]
    [OutputType([StanData])]
    param(
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "ArrayValue")]
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "ZeroValue")]
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "SequenceValue")]
        [string]$Name,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "ArrayValue")]
        [double[]]$Data,

        [Parameter(Position = 2, Mandatory = $false, ParameterSetName = "ArrayValue")]
        [Parameter(Position = 3, Mandatory = $false, ParameterSetName = "ZeroValue")]
        [Parameter(Position = 3, Mandatory = $false, ParameterSetName = "SequenceValue")]
        [int[]]$Dimensions,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "ZeroValue")]
        [ValidateSet("integer", "double")]
        [string]$Type,

        [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "ZeroValue")]
        [int]$Count,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "SequenceValue")]
        [double]$First,

        [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "SequenceValue")]
        [double]$Last
    )

    $stanValue = switch ($PSCmdlet.ParameterSetName) {
        "ArrayValue" {
            New-Object StanArrayData $Name, $Data
        }
        "ZeroValue" {
            New-Object StanZeroData $Name, $Type, $Count
        }
        "SequenceValue" {
            New-Object StanRangeData $Name, $First, $Last
        }
    }

    if ($null -ne $Dimensions -and $Dimensions.Count -gt 0) {
        $stanValue = New-Object StanStructureData $stanValue, $Dimensions
    }

    return $stanValue
}

function script:Write-StanData {
    param(
        [StanData]$Data,
        [bool]$AsString
    )

    if ($AsString) {
        $Data.ToString()
    }
    else {
        $Data
    }
}

function ConvertTo-StanData {
    [CmdletBinding()]
    [OutputType([StanData])]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [Parameter(Position = 1, Mandatory = $false)]
        [string]$DataCountName,

        [Parameter(Position = 2, Mandatory = $false)]
        [switch]$AsString
    )

    begin {
        $valueSet = New-Object "Dictionary[string, List[double]]"
    }

    process {
        foreach ($propName in $InputObject.PSObject.Properties.Name) {
            if (-not $valueSet.ContainsKey($propName)) {
                $valueSet[$propName] = New-Object List[double]
            }
            $valueSet[$propName].Add($InputObject.$propName)
        }
    }

    end {
        foreach ($key in $valueSet.Keys) {
            $value = $valueSet[$key]
            $count = $value.Count
            $data = New-StanData $key $value
            Write-StanData $data $AsString
        }

        if ($PSBoundParameters.ContainsKey("DataCountName")) {
            Write-StanData (New-StanData $DataCountName $count) $AsString
        }
    }
}