param([ValidateSet('debug', 'release')][string]$BuildMode = 'debug')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$devecoPath = Join-Path $env:ProgramFiles 'Huawei\DevEco Studio'
$env:DEVECO_SDK_HOME = Join-Path $devecoPath 'sdk'
$env:JAVA_HOME = Join-Path $devecoPath 'jbr'
$env:NODE_HOME = Join-Path $devecoPath 'tools\node'
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
$hvigorPath = Join-Path $devecoPath 'tools\hvigor\bin\hvigorw.bat'
if (!(Test-Path -LiteralPath $hvigorPath)) { throw '未找到 DevEco Studio，请检查安装目录。' }
Push-Location $projectPath
try {
  & $hvigorPath --mode module -p product=default -p module=entry@default -p buildMode=$BuildMode assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw '元服务编译失败' }
  & $hvigorPath --mode project -p product=default -p buildMode=$BuildMode assembleApp --no-daemon
  if ($LASTEXITCODE -ne 0) { throw '元服务 APP 打包失败' }
} finally { Pop-Location }
