Set-StrictMode -Version Latest

Describe "New-StanData" {

    It "can be created from an array" {
        $v = New-StanData abc 1, 2, 3
        $v.Name | Should -Be "abc"
        $v.Values | Should -Be 1, 2, 3
        $v.ToString() | Should -Be "abc <- c(1, 2, 3)"
    }

    It "can be created from a single value" {
        $v = New-StanData abc 999
        $v.Name | Should -Be "abc"
        $v.Values | Should -Be 999
        $v.ToString() | Should -Be "abc <- 999"
    }

    It "can be created from a type and a count" {
        $v = New-StanData abc -type integer -count 99
        $v.Name | Should -Be "abc"
        $v.Type | Should -Be "integer"
        $v.Count | Should -Be 99
        $v.ToString() | Should -Be "abc <- integer(99)"
    }

    It "can be created from first and last values" {
        $v = New-StanData abc -first 3 -last 9
        $v.Name | Should -Be "abc"
        $v.First | Should -Be 3
        $v.Last | Should -Be 9
        $v.ToString() | Should -Be "abc <- 3:9"
    }

    It "can be created as a structure value" {
        $v = New-StanData abc 1, 2, 3, 4 -dimensions 2, 2
        $v.Name | Should -Be "abc"
        $v.Dimensions | Should -Be 2, 2
        $v.ToString() | Should -Be "abc <- structure(c(1, 2, 3, 4), .Dim = c(2, 2))"
    }
}

Describe "ConverTo-StanData" {

    It "can convert objects to Stan values" {
        $value = @(
            [PSCustomObject]@{ x = 1; y = 10 }
            [PSCustomObject]@{ x = 2; y = 20 }
            [PSCustomObject]@{ x = 3; y = 30 }
        )

        $results = $value | ConvertTo-StanData

        $results.Length | Should -Be 2
        $results[0].Name | Should -Be "x"
        $results[0].Values | Should -Be 1, 2, 3
        $results[1].Name | Should -Be "y"
        $results[1].Values | Should -Be 10, 20, 30
    }

    It "can convert objects to R data format with -AsString" {
        $value = @(
            [PSCustomObject]@{ x = 1; y = 10 }
            [PSCustomObject]@{ x = 2; y = 20 }
            [PSCustomObject]@{ x = 3; y = 30 }
        )

        $results = $value | ConvertTo-StanData -AsString

        $results.Length | Should -Be 2
        $results[0] | Should -Be "x <- c(1, 2, 3)"
        $results[1] | Should -Be "y <- c(10, 20, 30)"
    }

    It "produces a data size element when -DataCountName is specified" {
        $value = @(
            [PSCustomObject]@{ x = 1; y = 10 }
            [PSCustomObject]@{ x = 2; y = 20 }
            [PSCustomObject]@{ x = 3; y = 30 }
        )

        $results = $value | ConvertTo-StanData -AsString -DataCountName N

        $results.Length | Should -Be 3
        $results[0] | Should -Be "x <- c(1, 2, 3)"
        $results[1] | Should -Be "y <- c(10, 20, 30)"
        $results[2] | Should -Be "N <- 3"

    }
}