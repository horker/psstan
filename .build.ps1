task . Build, ImportDebug, Test

Set-StrictMode -Version Latest

############################################################
# Settings
############################################################

$MODULE_NAME = "psstan"

$SCRIPT_PATH = "$PSScriptRoot\scripts"

$MODULE_PATH = "$PSScriptRoot\$MODULE_NAME"
$MODULE_PATH_DEBUG = "$PSScriptRoot\debug\$MODULE_NAME"

############################################################
# Helper cmdlets
############################################################

function New-Folder2 {
    param(
        [string]$Path
    )

    try {
        $null = New-Item -Type Directory $Path -EA Stop
        Write-Host -ForegroundColor DarkCyan "$Path created"
    }
    catch {
        Write-Host -ForegroundColor DarkYellow $_
    }
}

function Copy-Item2 {
    param(
        [string]$Source,
        [string]$Dest
    )

    try {
        Copy-Item $Source $Dest -EA Stop
        Write-Host -ForegroundColor DarkCyan "Copy from $Source to $Dest done"
    }
    catch {
        Write-Host -ForegroundColor DarkYellow $_
    }
}

function Remove-Item2 {
    param(
        [string]$Path
    )

    Resolve-Path $PATH | foreach {
        try {
            Remove-Item $_ -EA Stop -Recurse -Force
            Write-Host -ForegroundColor DarkCyan "$_ removed"
        }
        catch {
            Write-Host -ForegroundColor DarkYellow $_
        }
    }
}

############################################################
# Tasks
############################################################

task Build {
    . {
        $ErrorActionPreference = "Continue"

        function Copy-ObjectFiles {
            param(
                [string]$targetPath
            )

            New-Folder2 $targetPath
            Copy-Item2 "$SCRIPT_PATH\*" $targetPath
        }

        Copy-ObjectFiles $MODULE_PATH
        Copy-ObjectFiles $MODULE_PATH_DEBUG
    }
}

task Test Build, ImportDebug, {
    Invoke-Pester "$PSScriptRoot\tests"
}

task ImportDebug {
    Import-Module $MODULE_PATH_DEBUG -Force
}

task Clean {
    Remove-Item2 "$MODULE_PATH\*"
    Remove-Item2 "$MODULE_PATH_DEBUG\*"
}