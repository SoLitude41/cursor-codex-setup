<#
Collects YouTube video metadata and transcripts via the Supadata API
(https://supadata.ai) for every video listed in scripts/video-manifest.json,
and writes the result into research/youtube-transcripts/<slug>-video-01.md.

Usage:
  $env:SUPADATA_API_KEY = "your-key-here"
  pwsh scripts/collect-youtube-transcripts.ps1

The API key is read from the SUPADATA_API_KEY environment variable only.
It is never written to disk or committed.
#>

$ErrorActionPreference = "Stop"

if (-not $env:SUPADATA_API_KEY) {
    Write-Error "SUPADATA_API_KEY environment variable is not set. Run: `$env:SUPADATA_API_KEY = 'your-key'"
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot "scripts\video-manifest.json"
$outDir = Join-Path $repoRoot "research\youtube-transcripts"

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$today = Get-Date -Format "yyyy-MM-dd"

function Invoke-SupadataGet {
    param([string]$Uri)
    # Invoke-RestMethod/-WebRequest on Windows PowerShell 5.1 can misdetect the
    # response charset and mangle non-ASCII characters (e.g. curly quotes).
    # WebClient with an explicit UTF-8 encoding avoids that double-encoding bug.
    $client = New-Object System.Net.WebClient
    $client.Headers.Add("x-api-key", $env:SUPADATA_API_KEY)
    $client.Headers.Add("Content-Type", "application/json")
    $client.Encoding = [System.Text.Encoding]::UTF8
    $raw = $client.DownloadString($Uri)
    return $raw | ConvertFrom-Json
}

foreach ($entry in $manifest) {
    $slug = $entry.slug
    $videoId = $entry.videoId
    $expert = $entry.expert
    $annotation = $entry.annotation
    $videoUrl = "https://www.youtube.com/watch?v=$videoId"
    $outFile = Join-Path $outDir "$slug-video-01.md"

    Write-Host "Collecting: $expert ($videoId)..."

    try {
        $meta = Invoke-SupadataGet -Uri "https://api.supadata.ai/v1/youtube/video?id=$videoId"
    } catch {
        Write-Warning "  Metadata fetch failed for $expert : $_"
        $meta = $null
    }

    try {
        $transcript = Invoke-SupadataGet -Uri "https://api.supadata.ai/v1/youtube/transcript?videoId=$videoId&text=true"
    } catch {
        Write-Warning "  Transcript fetch failed for $expert : $_"
        $transcript = $null
    }

    $title = if ($meta) { $meta.title } else { "Not collected (API error)" }
    $channel = if ($meta -and $meta.channel) { $meta.channel.name } else { "Not collected (API error)" }
    $uploadDate = if ($meta -and $meta.uploadDate) { ([DateTime]$meta.uploadDate).ToString("yyyy-MM-dd") } else { "Not collected (API error)" }
    $transcriptStatus = if ($transcript -and $transcript.content) { "Collected via Supadata API on $today" } else { "Transcript not available via Supadata for this video as of $today" }
    $transcriptText = if ($transcript -and $transcript.content) {
        # Supadata returns some auto-caption transcripts with HTML entities
        # double-escaped (e.g. "you&amp;#39;re"). Decode twice to normalize
        # punctuation without altering any actual words.
        [System.Net.WebUtility]::HtmlDecode([System.Net.WebUtility]::HtmlDecode($transcript.content))
    } else {
        "No transcript was returned by the Supadata API for this video. Captions may be disabled or unavailable for this video."
    }

    $md = @"
# $expert - YouTube Video 01

Expert: $expert
YouTube URL: $videoUrl
Date added: 2026-07-02
Video title: $title
Channel: $channel
Published date: $uploadDate
Transcript status: $transcriptStatus

## Why This Source Was Selected

$annotation

## Transcript

$transcriptText

## Notes

Metadata and transcript collected programmatically via the Supadata API using scripts/collect-youtube-transcripts.ps1. Not manually edited or summarized.
"@

    Set-Content -Path $outFile -Value $md -Encoding utf8
    Write-Host "  Wrote $outFile"
    Start-Sleep -Milliseconds 500
}

Write-Host "Done."
