$ErrorActionPreference = "Stop"

Write-Host "Configure OpenAI API key for Morning Finance Brief."
Write-Host "Paste the full Platform API key. It should usually start with sk-."
Write-Host "The value will be saved to your Windows user environment variables."
Write-Host ""

$secure = Read-Host "OpenAI API key" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if (-not $key) { throw "Missing OpenAI API key." }
$key = $key.Trim()
if (-not $key.StartsWith("sk-")) {
    throw "This does not look like an OpenAI Platform API key. Expected it to start with sk-."
}

[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $key, "User")
Set-ItemProperty -Path "HKCU:\Environment" -Name "OPENAI_API_KEY" -Value $key

$suffix = $key.Substring([Math]::Max(0, $key.Length - 4))
Write-Host ""
Write-Host "OpenAI API key saved. Length: $($key.Length), suffix: $suffix"
Write-Host "Run send-morning-brief.ps1 to test."
