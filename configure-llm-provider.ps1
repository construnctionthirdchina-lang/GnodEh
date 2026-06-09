$ErrorActionPreference = "Stop"

function Read-Required {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    $suffix = if ($Default) { " [$Default]" } else { "" }
    $value = Read-Host "$Prompt$suffix"
    if (-not $value -and $Default) { $value = $Default }
    if (-not $value) { throw "Missing required value: $Prompt" }
    $value.Trim()
}

Write-Host "Configure an OpenAI-compatible LLM provider for Morning Finance Brief."
Write-Host "Examples:"
Write-Host "  DeepSeek:    base URL https://api.deepseek.com, model deepseek-chat"
Write-Host "  SiliconFlow: base URL https://api.siliconflow.com/v1, model from its model list"
Write-Host "  Kimi:        base URL https://api.moonshot.cn/v1, model from its model list"
Write-Host ""

$baseUrl = Read-Required -Prompt "LLM base URL" -Default "https://api.deepseek.com"
$model = Read-Required -Prompt "LLM model" -Default "deepseek-chat"
$secure = Read-Host "Provider API key" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}
if (-not $apiKey) { throw "Missing provider API key." }
$apiKey = $apiKey.Trim()

[Environment]::SetEnvironmentVariable("LLM_BASE_URL", $baseUrl, "User")
[Environment]::SetEnvironmentVariable("LLM_MODEL", $model, "User")
[Environment]::SetEnvironmentVariable("LLM_API_KEY", $apiKey, "User")
Set-ItemProperty -Path "HKCU:\Environment" -Name "LLM_BASE_URL" -Value $baseUrl
Set-ItemProperty -Path "HKCU:\Environment" -Name "LLM_MODEL" -Value $model
Set-ItemProperty -Path "HKCU:\Environment" -Name "LLM_API_KEY" -Value $apiKey

$suffix = $apiKey.Substring([Math]::Max(0, $apiKey.Length - 4))
Write-Host ""
Write-Host "LLM provider saved."
Write-Host "Base URL: $baseUrl"
Write-Host "Model: $model"
Write-Host "API key suffix: $suffix"
Write-Host "Run send-morning-brief.ps1 to test."
