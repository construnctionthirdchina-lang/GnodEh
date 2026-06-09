param(
    [string]$Recipient = "",
    [string]$OutputDir = "$PSScriptRoot\runs"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:OpenAiError = ""

function Get-ConfigValue {
    param(
        [string]$Name,
        [string]$Default = ""
    )
    $value = ""
    try {
        $value = (Get-ItemProperty -Path "HKCU:\Environment" -Name $Name -ErrorAction SilentlyContinue).$Name
    } catch {
        $value = ""
    }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, "Process") }
    if ($value) { return $value }
    $Default
}

function Get-NowCst {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("China Standard Time")
    [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
}

function Invoke-WebText {
    param([string]$Uri)
    $headers = @{
        "User-Agent" = "Mozilla/5.0 morning-finance-brief/1.0"
    }
    try {
        (Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec 25 -UseBasicParsing).Content
    } catch {
        ""
    }
}

function Invoke-WebJson {
    param([string]$Uri)
    $headers = @{
        "User-Agent" = "Mozilla/5.0 morning-finance-brief/1.0"
    }
    try {
        Invoke-RestMethod -Uri $Uri -Headers $headers -TimeoutSec 25
    } catch {
        $null
    }
}

function Invoke-JsonPostUtf8 {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body,
        [int]$TimeoutSec = 120
    )
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.Accept = "application/json"
    $request.Timeout = $TimeoutSec * 1000

    foreach ($key in $Headers.Keys) {
        if ($key -ne "Content-Type") {
            $request.Headers[$key] = [string]$Headers[$key]
        }
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Close()
    }

    try {
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        return ($text | ConvertFrom-Json)
    } catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response
        if ($webResponse) {
            $statusCode = [int]$webResponse.StatusCode
            $errorStream = $webResponse.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream, [System.Text.Encoding]::UTF8)
            $errorText = $reader.ReadToEnd()
            $reader.Close()
            $webResponse.Close()
            throw "HTTP $statusCode $errorText"
        }
        throw
    }
}

function ConvertTo-PlainText {
    param([string]$Html)
    if (-not $Html) { return "" }
    $text = $Html -replace "(?is)<script.*?</script>", " "
    $text = $text -replace "(?is)<style.*?</style>", " "
    $text = $text -replace "(?is)<[^>]+>", " "
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace "\s+", " "
    $text.Trim()
}

function Add-Article {
    param(
        [System.Collections.Generic.List[object]]$Articles,
        [string]$Title,
        [string]$Url,
        [string]$Source,
        [string]$SeenDate,
        [string]$Snippet
    )
    if (-not $Title -or -not $Url) { return }
    if ($Articles | Where-Object { $_.url -eq $Url }) { return }
    $Articles.Add([pscustomobject]@{
        title = ($Title -replace "\s+", " ").Trim()
        url = $Url
        source = $Source
        seenDate = $SeenDate
        snippet = (($Snippet -replace "\s+", " ").Trim())
    }) | Out-Null
}

function Search-Gdelt {
    param(
        [string]$Query,
        [int]$MaxRecords = 8
    )
    $encoded = [uri]::EscapeDataString($Query)
    $uri = "https://api.gdeltproject.org/api/v2/doc/doc?query=$encoded&mode=artlist&format=json&sort=hybridrel&timespan=1d&maxrecords=$MaxRecords"
    $json = Invoke-WebJson -Uri $uri
    if (-not $json -or -not $json.articles) { return @() }
    $json.articles
}

function Search-GoogleNewsRss {
    param(
        [string]$Query,
        [int]$MaxRecords = 6
    )
    $encoded = [uri]::EscapeDataString($Query)
    $uri = "https://news.google.com/rss/search?q=$encoded&hl=en-US&gl=US&ceid=US:en"
    $xmlText = Invoke-WebText -Uri $uri
    if (-not $xmlText) { return @() }
    try {
        [xml]$xml = $xmlText
        $items = @($xml.rss.channel.item) | Select-Object -First $MaxRecords
        return $items | ForEach-Object {
            [pscustomobject]@{
                title = [string]$_.title
                url = [string]$_.link
                source = [string]$_.source.'#text'
                seenDate = [string]$_.pubDate
                snippet = [string]$_.description
            }
        }
    } catch {
        @()
    }
}

function Get-OfficialSourcePack {
    $sources = New-Object System.Collections.Generic.List[object]
    $officialPages = @(
        "https://www.federalreserve.gov/newsevents/2026-speeches.htm",
        "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm",
        "https://www.whitehouse.gov/briefing-room/",
        "https://www.whitehouse.gov/presidential-actions/"
    )

    foreach ($url in $officialPages) {
        $html = Invoke-WebText -Uri $url
        $plain = ConvertTo-PlainText -Html $html
        if ($plain.Length -gt 1800) { $plain = $plain.Substring(0, 1800) }
        Add-Article -Articles $sources -Title $url -Url $url -Source "official" -SeenDate "" -Snippet $plain
    }
    $sources
}

function Get-SourcePack {
    $articles = New-Object System.Collections.Generic.List[object]
    $queries = @(
        'global markets stocks dollar treasury yields oil gold Reuters OR Bloomberg OR "Wall Street Journal" OR FT',
        'Federal Reserve Powell Waller Bowman Williams Jefferson speech rates Reuters OR Bloomberg OR "Federal Reserve"',
        'Trump tariffs Israel Iran oil markets Reuters OR AP OR Bloomberg OR "White House"',
        'gold price Fed rate hike oil Middle East Reuters',
        'bitcoin crypto dollar rates risk assets Reuters CNBC',
        'AI stocks Nvidia Broadcom AMD Micron semiconductor selloff Reuters CNBC',
        'software stocks AI Salesforce ServiceNow Datadog Snowflake Reuters CNBC'
    )

    foreach ($query in $queries) {
        foreach ($article in (Search-Gdelt -Query $query -MaxRecords 6)) {
            Add-Article -Articles $articles -Title $article.title -Url $article.url -Source $article.domain -SeenDate $article.seendate -Snippet $article.socialimage
        }
        foreach ($article in (Search-GoogleNewsRss -Query "$query when:1d" -MaxRecords 4)) {
            Add-Article -Articles $articles -Title $article.title -Url $article.url -Source $article.source -SeenDate $article.seenDate -Snippet (ConvertTo-PlainText $article.snippet)
        }
    }

    foreach ($official in (Get-OfficialSourcePack)) {
        $articles.Add($official) | Out-Null
    }

    $articles | Select-Object -First 60
}

function New-FallbackBrief {
    param(
        [array]$Articles,
        [DateTime]$Now
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Morning Finance Brief | $($Now.ToString("yyyy-MM-dd HH:mm")) Beijing Time") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Key Conclusions") | Out-Null
    $lines.Add("1. Source candidates from the last 24 hours were collected. OPENAI_API_KEY is not configured, so this is a sourced fallback list rather than a polished Chinese summary.") | Out-Null
    $lines.Add("2. Configure OPENAI_API_KEY to generate the requested concise Simplified Chinese briefing with the exact section format.") | Out-Null
    $lines.Add("") | Out-Null

    $sections = [ordered]@{
        "Gold" = "gold|oil|rate|Fed"
        "Crypto" = "bitcoin|crypto|ether|stablecoin"
        "US AI Stocks" = "AI|Nvidia|Broadcom|AMD|Micron|semiconductor|chip"
        "US Software Stocks" = "software|Salesforce|ServiceNow|Datadog|Snowflake|Oracle|Microsoft"
        "Macro/Fed/Trump" = "Federal Reserve|Fed|Powell|Waller|Bowman|Trump|White House|dollar|Treasury|tariff"
    }

    foreach ($section in $sections.Keys) {
        $lines.Add($section) | Out-Null
        $picked = @($Articles | Where-Object { ($_.title + " " + $_.snippet + " " + $_.source) -match $sections[$section] } | Select-Object -First 3)
        if ($picked.Count -eq 0) {
            $lines.Add("- No authoritative major update found.") | Out-Null
        } else {
            foreach ($item in $picked) {
                $lines.Add("- $($item.title) [$($item.source)] $($item.url)") | Out-Null
            }
        }
        $lines.Add("") | Out-Null
    }

    $lines.Add("Watch Today") | Out-Null
    $lines.Add("- US economic calendar, Fed official schedule, Middle East energy/Hormuz headlines, and AI/software spillover after the US open.") | Out-Null
    ($lines -join "`r`n")
}

function New-OpenAiBrief {
    param(
        [array]$Articles,
        [DateTime]$Now
    )
    $apiKey = Get-ConfigValue -Name "LLM_API_KEY"
    if (-not $apiKey) { $apiKey = Get-ConfigValue -Name "OPENAI_API_KEY" }
    if (-not $apiKey) { return $null }
    $model = Get-ConfigValue -Name "LLM_MODEL"
    if (-not $model) { $model = Get-ConfigValue -Name "OPENAI_MODEL" -Default "gpt-4o-mini" }
    $baseUrl = Get-ConfigValue -Name "LLM_BASE_URL" -Default "https://api.openai.com/v1"
    $baseUrl = $baseUrl.TrimEnd("/")
    $endpoint = if ($baseUrl -match "/chat/completions$") { $baseUrl } else { "$baseUrl/chat/completions" }
    $sourceJson = $Articles | ConvertTo-Json -Depth 5 -Compress
    if ($sourceJson.Length -gt 30000) {
        $sourceJson = $sourceJson.Substring(0, 30000)
    }

    $prompt = @"
You are a strict morning financial brief editor. Current time: $($Now.ToString("yyyy-MM-dd HH:mm")) Beijing Time.
Use only the source pack below. Output Simplified Chinese only. The final email should look like a concise Codex answer, not a source dump.

Hard output format, translated into natural Simplified Chinese:
Title line: Morning Financial Brief | YYYY-MM-DD HH:mm Beijing Time
Section 1: Most important conclusions, numbered 1-5 at most
Section 2: Gold
Section 3: Cryptocurrency
Section 4: US AI stocks
Section 5: US software stocks
Section 6: Macro / Fed / Trump
Final section: Today's key times, data, and speeches to watch

Rules:
- No English section headings.
- No raw source list.
- Do not include Markdown source links unless they are essential; the user prefers clean readable text.
- Every factual claim must be directly supported by a title, snippet, official page text, or source metadata in the source pack.
- If the source pack only has a headline, summarize only what the headline supports. Do not invent numbers, prices, dates, names, or market moves.
- Prioritize the past 24 hours and facts most likely to affect trading and asset pricing.
- First section: no more than 5 conclusions.
- Five asset sections: 1-3 bullets each. Each bullet must be no more than two short sentences.
- Fed remarks must include speaker, date, and core policy signal when the source pack supports them.
- Trump items must distinguish fact, summarized remark, and likely market impact when supported.
- If a section has no authoritative major update, write one short Simplified Chinese bullet meaning: no authoritative major update for now.
- If the source pack is too weak to produce a reliable brief, output exactly: "ERROR: insufficient reliable sources".

Source pack JSON:
$sourceJson
"@

    $body = @{
        model = $model
        temperature = 0.2
        messages = @(
            @{
                role = "system"
                content = "You produce concise, accurate Simplified Chinese financial briefings. Use only provided sources."
            },
            @{
                role = "user"
                content = $prompt
            }
        )
    } | ConvertTo-Json -Depth 8

    $headers = @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type" = "application/json"
    }

    try {
        $response = $null
        $lastError = ""
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $response = Invoke-JsonPostUtf8 -Uri $endpoint -Headers $headers -Body $body -TimeoutSec 120
                break
            } catch {
                $lastError = $_.Exception.Message
                if ($lastError -notmatch "429|Too Many Requests" -or $attempt -eq 3) {
                    throw
                }
                Start-Sleep -Seconds ([Math]::Min(30, 5 * $attempt))
            }
        }
        if (-not $response) { throw $lastError }
        $result = ""
        if ($response.choices -and $response.choices.Count -gt 0) {
            $result = [string]$response.choices[0].message.content
        }
        $result = $result.Trim()
        if ($result -eq "ERROR: insufficient reliable sources") {
            $script:OpenAiError = "Insufficient reliable sources for a concise Chinese brief."
            return $null
        }
        return $result
    } catch {
        $script:OpenAiError = $_.Exception.Message
        return $null
    }
}

function Send-BriefMail {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$To
    )
    $hostName = Get-ConfigValue -Name "MFB_SMTP_HOST"
    $port = [int](Get-ConfigValue -Name "MFB_SMTP_PORT" -Default "465")
    $user = Get-ConfigValue -Name "MFB_SMTP_USER"
    $pass = Get-ConfigValue -Name "MFB_SMTP_PASS"
    $from = Get-ConfigValue -Name "MFB_FROM" -Default $user

    if (-not $hostName -or -not $user -or -not $pass -or -not $from) {
        return "SKIPPED: SMTP env vars missing. Required: MFB_SMTP_HOST, MFB_SMTP_USER, MFB_SMTP_PASS; optional: MFB_SMTP_PORT, MFB_FROM, MFB_TO."
    }

    $recipients = @($To -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($recipients.Count -eq 0) {
        return "SKIPPED: no recipients configured."
    }

    if ($port -eq 465) {
        Send-SmtpImplicitSsl -HostName $hostName -Port $port -User $user -Password $pass -From $from -To $recipients -Subject $Subject -Body $Body
    } else {
        $message = New-Object System.Net.Mail.MailMessage
        $message.From = $from
        foreach ($recipient in $recipients) {
            $message.To.Add($recipient)
        }
        $message.Subject = $Subject
        $message.Body = $Body
        $message.BodyEncoding = [System.Text.Encoding]::UTF8
        $message.SubjectEncoding = [System.Text.Encoding]::UTF8

        $client = New-Object System.Net.Mail.SmtpClient($hostName, $port)
        $client.EnableSsl = $true
        $client.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $client.Send($message)
    }
    "SENT: $($recipients -join ',')"
}

function Read-SmtpResponse {
    param([System.IO.StreamReader]$Reader)
    $lines = @()
    while ($true) {
        $line = $Reader.ReadLine()
        if ($null -eq $line) { throw "SMTP connection closed unexpectedly." }
        $lines += $line
        if ($line.Length -lt 4 -or $line.Substring(3, 1) -eq " ") { break }
    }
    $lines
}

function Send-SmtpCommand {
    param(
        [System.IO.StreamReader]$Reader,
        [System.IO.StreamWriter]$Writer,
        [string]$Command,
        [int[]]$ExpectedCodes
    )
    if ($Command) {
        $Writer.WriteLine($Command)
        $Writer.Flush()
    }
    $response = Read-SmtpResponse -Reader $Reader
    $code = if ($response[0].Length -ge 3) { [int]$response[0].Substring(0, 3) } else { 0 }
    $ok = $false
    foreach ($expected in $ExpectedCodes) {
        if ($code -eq [int]$expected) {
            $ok = $true
            break
        }
    }
    if (-not $ok) {
        throw "SMTP command failed with $($response -join ' | ')"
    }
    $response
}

function Assert-SmtpCode {
    param(
        [string[]]$Response,
        [int[]]$ExpectedCodes
    )
    $code = if ($Response[0].Length -ge 3) { [int]$Response[0].Substring(0, 3) } else { 0 }
    foreach ($expected in $ExpectedCodes) {
        if ($code -eq [int]$expected) { return }
    }
    throw "SMTP command failed with $($Response -join ' | ')"
}

function Write-SmtpLine {
    param(
        [System.IO.StreamWriter]$Writer,
        [string]$Line
    )
    $Writer.WriteLine($Line)
    $Writer.Flush()
}

function ConvertTo-Rfc2047Subject {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    "=?UTF-8?B?$([Convert]::ToBase64String($bytes))?="
}

function ConvertTo-Base64Lines {
    param([string]$Text)
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $base64.Length; $i += 76) {
        $parts.Add($base64.Substring($i, [Math]::Min(76, $base64.Length - $i))) | Out-Null
    }
    $parts -join "`r`n"
}

function Send-SmtpImplicitSsl {
    param(
        [string]$HostName,
        [int]$Port,
        [string]$User,
        [string]$Password,
        [string]$From,
        [string[]]$To,
        [string]$Subject,
        [string]$Body
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect($HostName, $Port)
        $ssl = New-Object System.Net.Security.SslStream($client.GetStream(), $false)
        $ssl.AuthenticateAsClient($HostName)
        $reader = New-Object System.IO.StreamReader($ssl, [System.Text.Encoding]::ASCII)
        $writer = New-Object System.IO.StreamWriter($ssl, [System.Text.Encoding]::ASCII)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true

        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(220)
        Write-SmtpLine -Writer $writer -Line "EHLO localhost"
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(250)
        Write-SmtpLine -Writer $writer -Line "AUTH LOGIN"
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(334)
        Write-SmtpLine -Writer $writer -Line ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($User)))
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(334)
        Write-SmtpLine -Writer $writer -Line ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Password)))
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(235)
        Write-SmtpLine -Writer $writer -Line "MAIL FROM:<$From>"
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(250)
        foreach ($recipient in $To) {
            Write-SmtpLine -Writer $writer -Line "RCPT TO:<$recipient>"
            Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(250, 251)
        }
        Write-SmtpLine -Writer $writer -Line "DATA"
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(354)

        $message = @(
            "From: <$From>",
            "To: $((@($To) | ForEach-Object { '<' + $_ + '>' }) -join ', ')",
            "Subject: $(ConvertTo-Rfc2047Subject -Text $Subject)",
            "Date: $([DateTime]::UtcNow.ToString('r'))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            (ConvertTo-Base64Lines -Text $Body)
        ) -join "`r`n"

        $writer.WriteLine($message)
        $writer.WriteLine(".")
        $writer.Flush()
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(250)
        Write-SmtpLine -Writer $writer -Line "QUIT"
        Assert-SmtpCode -Response (Read-SmtpResponse -Reader $reader) -ExpectedCodes @(221)
    } finally {
        if ($client) { $client.Close() }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$now = Get-NowCst
$Recipient = if ($Recipient) { $Recipient } else { Get-ConfigValue -Name "MFB_TO" -Default "747327615@qq.com" }
$stamp = $now.ToString("yyyyMMdd-HHmmss")
$articles = @(Get-SourcePack)
$brief = New-OpenAiBrief -Articles $articles -Now $now
if (-not $brief) {
    $errorText = if ($script:OpenAiError) { $script:OpenAiError } else { "OpenAI summary did not return content." }
    $brief = "MFB_OPENAI_FAILED`r`n`r`nReason: $errorText`r`n`r`nNo fallback source-list email was sent because the user requires the concise Chinese brief format."
}

$subject = "Morning Finance Brief $($now.ToString("yyyy-MM-dd"))"
$briefPath = Join-Path $OutputDir "$stamp-brief.md"
$sourcePath = Join-Path $OutputDir "$stamp-sources.json"
$statusPath = Join-Path $OutputDir "$stamp-status.txt"

$brief | Set-Content -Path $briefPath -Encoding UTF8
$articles | ConvertTo-Json -Depth 5 | Set-Content -Path $sourcePath -Encoding UTF8
if ($brief -like "MFB_OPENAI_FAILED*") {
    $status = "FAILED: $($brief -replace "`r?`n", " ")"
    $status | Set-Content -Path $statusPath -Encoding UTF8
    Write-Output $status
    Write-Output "BRIEF: $briefPath"
    Write-Output "SOURCES: $sourcePath"
    exit 1
}
$mailStatus = Send-BriefMail -Subject $subject -Body $brief -To $Recipient
$mailStatus | Set-Content -Path $statusPath -Encoding UTF8

Write-Output $mailStatus
Write-Output "BRIEF: $briefPath"
Write-Output "SOURCES: $sourcePath"
