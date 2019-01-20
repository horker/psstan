using namespace System.Collections.Generic

Set-StrictMode -Version Latest

$PSSTAN_TOOLS_PATHS = @(
    "$HOME\Documents\apps\RTools\bin",
    "$HOME\Documents\apps\Rtools\mingw_64\bin"
)

$PSSTAN_PATH = "$HOME\work\stan\cmdstan"

function New-StanExecutable {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MakeOptions
    )

    $Path = try { Resolve-Path $Path } catch { $_.TargetObject }
    $Path = $Path -Replace "\.stan$", ".exe"
    $Path = $Path -Replace "\\", "/"
    $oldPath = $env:Path
    try {
        $env:Path = $PSSTAN_TOOLS_PATHS -join ";"
        Push-Location $PSSTAN_PATH
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
        $env:Path = $PSSTAN_TOOLS_PATHS -join ";"
        $commandLine = "$PSSTAN_PATH\bin\stansummary '$Path' $($options -join " ")"
        Invoke-Expression $commandLine
    }
    finally {
        $env:Path = $oldPath
    }
}

function Show-StanSummary {
    [CmdletBinding()]
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
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$Autocorr
    )

    $file = [IO.Path]::GetTempFileName()
    $PSBoundParameters.Add("CsvFile", $file)
    $null = Invoke-StanSummary $PSBoundParameters

    $parameters = Get-Content $file |
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