# Morning Finance Brief Email

This local automation generates a Chinese morning financial brief and sends it to `747327615@qq.com`.

## What It Does

- Runs the briefing script daily at 10:00 Beijing time when installed with `install-scheduled-task.ps1`.
- Collects market/Fed/Trump/gold/crypto/AI/software source candidates from authoritative news and official pages.
- Uses `OPENAI_API_KEY` when available to produce the polished Chinese format requested.
- Requires a valid `OPENAI_API_KEY` for the polished Chinese brief; it will not email a sourced fallback list.
- Sends email through SMTP using environment variables.
- Writes each run to `runs\` for audit/debugging.

## Required Environment Variables

For email delivery:

```powershell
setx MFB_SMTP_HOST "smtp.qq.com"
setx MFB_SMTP_PORT "465"
setx MFB_SMTP_USER "your-sender@qq.com"
setx MFB_SMTP_PASS "your-qq-smtp-authorization-code"
setx MFB_FROM "your-sender@qq.com"
setx MFB_TO "747327615@qq.com"
```

Or run the interactive local helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\configure-smtp.ps1
```

This prompts for the sender email and SMTP authorization code locally, so the code does not need to be pasted into chat.

For polished Chinese summarization with OpenAI-compatible providers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\configure-llm-provider.ps1
```

This writes:

```powershell
LLM_BASE_URL
LLM_MODEL
LLM_API_KEY
```

Examples:

- DeepSeek: `https://api.deepseek.com`, model `deepseek-chat`
- SiliconFlow: `https://api.siliconflow.com/v1`, model from its model list
- Kimi: `https://api.moonshot.cn/v1`, model from its model list

OpenAI remains supported as a fallback:

```powershell
setx OPENAI_API_KEY "your-openai-api-key"
setx OPENAI_MODEL "gpt-4o-mini"
```

Or run the interactive local helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\configure-openai-key.ps1
```

After `setx`, open a new terminal/session before running the task so the new environment variables are visible.

## Install Daily Task

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-scheduled-task.ps1
```

## Cloud Scheduling With GitHub Actions

The local Windows task depends on the PC being awake. For reliable delivery when the PC is asleep or off, use the included GitHub Actions workflow:

```text
.github\workflows\morning-finance-brief.yml
```

It runs every day at 02:00 UTC, which is 10:00 Beijing time, and can also be triggered manually from the GitHub Actions tab.

Create a private GitHub repository, upload this folder, then add these repository secrets under:

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

Required secrets:

```text
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-chat
LLM_API_KEY=<your provider API key>
MFB_SMTP_HOST=smtp.qq.com
MFB_SMTP_PORT=465
MFB_SMTP_USER=<sender email>
MFB_SMTP_PASS=<smtp authorization code>
MFB_FROM=<sender email>
MFB_TO=hd747327615@163.com,1070172690@qq.com
```

After secrets are configured, open the repository's Actions tab, choose "Morning Finance Brief", and click "Run workflow" once to test.

## Test A Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\send-morning-brief.ps1
```

Check the latest files in `runs\` if email is skipped or fails.

## Notes

- QQ Mail requires an SMTP authorization code, not your normal QQ password.
- If SMTP variables are missing, the script intentionally skips sending and saves the generated brief locally.
- If `OPENAI_API_KEY` is missing or the OpenAI call fails, the script writes a failure status locally and does not send a malformed fallback brief.
- GitHub Actions schedules can run a few minutes late, but they do not depend on your PC being powered on.
