$key = cat $PSScriptRoot\..\private\NugetApiKey.txt

Publish-Module -Path $PSScriptRoot\..\psstan -NugetApiKey $key -Verbose