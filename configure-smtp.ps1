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
    $value
}

Write-Host "Configure Morning Finance Brief SMTP settings."
Write-Host "Use your email SMTP authorization code, not your normal login password."
Write-Host "Values are stored in your Windows user environment variables."
Write-Host ""

$smtpHost = Read-Required -Prompt "SMTP host" -Default "smtp.qq.com"
$smtpPort = Read-Required -Prompt "SMTP port" -Default "465"
$smtpUser = Read-Required -Prompt "Sender email"
$smtpPassSecure = Read-Host "SMTP authorization code" -AsSecureString
$smtpPassPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($smtpPassSecure)
try {
    $smtpPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($smtpPassPtr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($smtpPassPtr)
}
if (-not $smtpPass) { throw "Missing SMTP authorization code." }

$from = Read-Required -Prompt "From email" -Default $smtpUser
$to = Read-Required -Prompt "Recipient email" -Default "747327615@qq.com"

[Environment]::SetEnvironmentVariable("MFB_SMTP_HOST", $smtpHost, "User")
[Environment]::SetEnvironmentVariable("MFB_SMTP_PORT", $smtpPort, "User")
[Environment]::SetEnvironmentVariable("MFB_SMTP_USER", $smtpUser, "User")
[Environment]::SetEnvironmentVariable("MFB_SMTP_PASS", $smtpPass, "User")
[Environment]::SetEnvironmentVariable("MFB_FROM", $from, "User")
[Environment]::SetEnvironmentVariable("MFB_TO", $to, "User")

Write-Host ""
Write-Host "SMTP settings saved. Run send-morning-brief.ps1 to send a test email."
