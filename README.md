# psstan

This is a module to provide cmdlets to use Stan nicely in PowerShell.

This module is built on top of CmdStan v2.18.1.

## Installation

This module is available in [PowerShell Gallery](https://www.powershellgallery.com/packages/psstan).

```powershell
Install-Module -Scope CurrentUser psstan
```

## Configuration

1. Download and install CmdStan according to the guidance of [the official site of CmdStan](https://mc-stan.org/users/interfaces/cmdstan.html). The documentation "CmdStan Interface User's Guide" available on [the release page](https://github.com/stan-dev/cmdstan/releases) contains the step-by-step instructions to install CmdStan in Windows.

2. Define the variables `$PSSTAN_PATH` and `$PSSTAN_TOOLS_PATHS` (in your `profile.ps1`, for example). The former should be set to the directory where CmdStan is installed. The latter an array of the directories where `g++` and `make` to compile Stan models are installed. For example:

```PowerShell
$PSSTAN_PATH = "C:\your_app_path\cmdstan"
$PSSTAN_TOOLS_PATHS = @(
    "C:\RTools\bin"
    "C:\RTools\mingw_64\bin"
)
```

## Examples

### Example 1

The following session shows how to compile and train the `bernoulli` example model included in the CmdStan source code tree.

```PowerShell
PS> cd C:\your_app_path\cmdstan\examples\bernoulli
PS> New-StanExecutable bernoulli.stan
:
(snip)
:
PS> .\bernoulli.exe sample data file=bernoulli.data.R
:
(snip)
:
PS> Show-StanSummary output.csv
Inference for Stan model: bernoulli_model
1 chains: each with iter=(1000); warmup=(0); thin=(1); 1000 iterations saved.

Warmup took (0.011) seconds, 0.011 seconds total
Sampling took (0.043) seconds, 0.043 seconds total

                Mean     MCSE   StdDev     5%   50%   95%    N_Eff  N_Eff/s    R_hat
lp__            -7.3 3.3e-002 7.3e-001   -8.8  -7.0  -6.8 4.8e+002 1.1e+004 1.0e+000
accept_stat__   0.91 4.4e-003 1.4e-001   0.63  0.97   1.0 9.8e+002 2.3e+004 1.0e+000
stepsize__       1.1 2.2e-015 1.6e-015    1.1   1.1   1.1 5.0e-001 1.2e+001 1.0e+000
treedepth__      1.4 1.7e-002 4.9e-001    1.0   1.0   2.0 8.2e+002 1.9e+004 1.0e+000
n_leapfrog__     2.3 3.2e-002 9.7e-001    1.0   3.0   3.0 9.2e+002 2.1e+004 1.0e+000
divergent__     0.00      nan 0.0e+000   0.00  0.00  0.00      nan      nan      nan
energy__         7.8 4.7e-002 9.7e-001    6.8   7.5   9.7 4.3e+002 1.0e+004 1.0e+000
theta           0.24 7.4e-003 1.2e-001  0.075  0.23  0.45 2.6e+002 6.1e+003 1.0e+000

Samples were drawn using hmc with nuts.
For each parameter, N_Eff is a crude measure of effective sample size,
and R_hat is the potential scale reduction factor on split chains (at
convergence, R_hat=1).

PS> $params = Get-StanSummary output.csv
PS> $params.theta

name    : theta
Mean    : 0.244519
MCSE    : 0.00736044
StdDev  : 0.119169
5%      : 0.0748537
50%     : 0.229183
95%     : 0.45154
N_Eff   : 262.133
N_Eff/s : 6096.12
R_hat   : 1.00098

PS>
```

### Example 2

The following example shows how to prapare R data format files by the `ConvertTo-StanData` cmdlet.

```PowerShell
PS> Get-Content example.csv
age,income
21,413
34,599
40,779
PS> Import-Csv example.csv | ConvertTo-StanData -DataCountName N | Set-Content example.data.R
PS> Get-Content example.data.R
age <- c(21, 34, 40)
income <- c(413, 599, 779)
N <- 3
```

### Example 3

The following example shows to how to generate records in the R data format programatically.

```PowerShell
PS> New-StanData array 10, 20, 30, 40 | Set-Content example2.data.R
PS> New-StanData struct 1, 0, 0, 0, 1, 0, 0, 0,0, 1 -Dimensions 3, 3 | Add-Content example2.data.R
PS> New-StanData zero_values -Type double -Count 10 | Add-Content example2.data.R
PS> New-StanData range -First 100 -Last 200 | Add-Content example2.data.R
PS> Get-Content example2.data.R
array <- c(10, 20, 30, 40)
struct <- structure(c(1, 0, 0, 0, 1, 0, 0, 0, 0, 1), .Dim = c(3, 3))
zero_values <- double(10)
range <- 100:200
```

## License

This module is licensed under the MIT License. See LICENSE.txt for more information.