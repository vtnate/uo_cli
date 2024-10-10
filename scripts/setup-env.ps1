# This is a simple setup script that generates an environment file that
# is used to setup the ruby environment to run the urbanopt-cli tool.
# To use just run this script in powershell (e.g. ./setup-env.ps1)
# Then you can use this env.ps1 to setup the environment.
# (e.g. . env.ps1)

if (-not (Test-Path $HOME)) { echo "env HOME needs to be set before running this script" }
if (-not (Test-Path $HOME)) { exit }

# uo install_python will install its own python within the gem directories so we need to find the python path and add it to $env.PATH
$output = Get-ChildItem -ErrorAction SilentlyContinue -Directory "C:\URBANopt*" -Recurse -Filter "python-3.10" | Select-Object FullName

if ($output.FullName) { 
  $RUBY_PYTHON_PATH = $output.FullName 
}
else {
  $RUBY_PYTHON_PATH = ""
}


$BASE_DIR_NAME = $PSScriptRoot

$env:GEM_HOME      = "$BASE_DIR_NAME\gems\ruby\2.7.0"
$env:GEM_PATH      = "$BASE_DIR_NAME\gems\ruby\2.7.0"
$env:PATH         += ";$BASE_DIR_NAME\ruby\bin;$BASE_DIR_NAME\gems\ruby\2.7.0\bin;$RUBY_PYTHON_PATH"
$env:RUBYLIB       = "$BASE_DIR_NAME\OpenStudio\Ruby"
$env:RUBY_DLL_PATH = "$BASE_DIR_NAME\OpenStudio\Ruby"

# Remove if exists
Remove-Item $HOME/.env_uo.ps1 -ErrorAction Ignore

'$env:GEM_HOME       = "' + $env:GEM_HOME + '"'   >> $HOME/.env_uo.ps1
'$env:GEM_PATH       = "' + $env:GEM_PATH + '"'   >> $HOME/.env_uo.ps1
'$env:PATH           = "' + $env:PATH     + '"'   >> $HOME/.env_uo.ps1
'$env:RUBYLIB        = "' + $env:RUBYLIB  + '"'   >> $HOME/.env_uo.ps1
'$env:RUBY_DLL_PATH  = "' + $env:RUBY_DLL_PATH  + '"'   >> $HOME/.env_uo.ps1 
