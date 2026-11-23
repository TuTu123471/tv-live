# Builds hd.m3u and lunbo.m3u for the TV playlist.
# Runs on Windows (local) and on GitHub Actions (pwsh on ubuntu).
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
$utf = [System.Text.Encoding]::UTF8
$gbk = [System.Text.Encoding]::GetEncoding(936)
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'

function Str([int[]]$codes) { ($codes | ForEach-Object { [string][char]$_ }) -join '' }

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Fetch-Text($url) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ((New-Guid).ToString('N') + '.tmp')
    try {
        Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = $ua } -TimeoutSec 40 -UseBasicParsing -OutFile $tmp
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        $t = $utf.GetString($bytes)
        $bad = ([regex]::Matches($t, [regex]::Escape([string][char]0xFFFD))).Count
        if ($bad -gt [Math]::Max(20, $t.Length / 200)) { $t = $gbk.GetString($bytes) }
        return $t
    } catch {
        Write-Host ("fetch failed: " + $url + " :: " + $_.Exception.Message)
        return $null
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Parse-Entries($text) {
    $out = @()
    $lines = ($text -split "\r?\n|\r")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if ($l -eq '' -or $l -match '^https?://\S+$') { continue }
        if ($l -match '^#EXTINF') {
            $grp = ''
            if ($l -match 'group-title="([^"]*)"') { $grp = $matches[1] }
            $name = ''
            $idx = $l.LastIndexOf(',')
            if ($idx -ge 0) { $name = $l.Substring($idx + 1).Trim() }
            $j = $i + 1
            while ($j -lt $lines.Count -and ($lines[$j].Trim() -eq '' -or $lines[$j].Trim().StartsWith('#'))) { $j++ }
            if ($j -lt $lines.Count -and $lines[$j].Trim() -match '^https?://') {
                $out += [pscustomobject]@{ name = $name; url = $lines[$j].Trim(); group = $grp }
            }
        } elseif ($l -match '^([^,]+),(https?://\S+)$') {
            $out += [pscustomobject]@{ name = $matches[1].Trim(); url = $matches[2].Trim(); group = '' }
        }
    }
    foreach ($e in $out) { $e.name = ($e.name -replace '\s*https?://\S+', '').Trim() }
    return ($out | Where-Object { $_.name -ne '' })
}

$testWorker = {
    param($url)
    $res = [pscustomobject]@{ ok = $false; ttfb = -1; codec = 'unknown' }
    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = 'GET'
        $req.AllowAutoRedirect = $true
        $req.MaximumAutomaticRedirections = 6
        $req.Timeout = 12000
        $req.ReadWriteTimeout = 6000
        $req.UserAgent = 'Mozilla/5.0'
        $resp = $req.GetResponse()
        $res.ttfb = 0
        $s = $resp.GetResponseStream()
        $s.ReadTimeout = 6000
        $buf = New-Object byte[] 32768
        $total = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($total -lt 32768 -and $sw.ElapsedMilliseconds -lt 6000) {
            $n = $s.Read($buf, $total, 32768 - $total)
            if ($n -le 0) { break }
            $total += $n
        }
        $res.ttfb = $sw.ElapsedMilliseconds
        $res.ok = ($total -gt 0)
        if ($total -gt 0 -and $buf[0] -eq 0x46 -and $buf[1] -eq 0x4C) {
            $p = 13
            $guard = 0
            while ($p + 11 -lt $total -and $guard -lt 300) {
                $t = [int]$buf[$p]
                $ds = ([int]$buf[$p+1] -shl 16) -bor ([int]$buf[$p+2] -shl 8) -bor [int]$buf[$p+3]
                if ($t -eq 9) {
                    $cid = [int]$buf[$p+11] -band 0x0F
                    if ($cid -eq 12) { $res.codec = 'HEVC'; break }
                    if ($cid -eq 7) { $res.codec = 'AVC'; break }
                    if ($cid -eq 2) { $res.codec = 'H263'; break }
                } elseif ($t -ne 8 -and $t -ne 18) {
                    break
                }
                $next = $p + 11 + $ds + 4
                if ($next -le $p) { break }
                $p = $next
                $guard++
            }
        } else {
            $res.codec = 'HLS'
        }
        try { $s.Close(); $resp.Close() } catch {}
    } catch {
        $res.ok = $false
    }
    return $res
}

function Test-List($entries, $workers) {
    $pool = [runspacefactory]::CreateRunspacePool(1, $workers)
    $pool.Open()
    $jobs = @()
    foreach ($e in $entries) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($testWorker).AddArgument($e.url)
        $jobs += [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke(); src = $e }
    }
    $out = @()
    foreach ($j in $jobs) {
        while (-not $j.h.IsCompleted) { Start-Sleep -Milliseconds 100 }
        $r = $null
        try { $r = $j.ps.EndInvoke($j.h) } catch {}
        if ($r -and $r.ok) {
            $out += [pscustomobject]@{ group = $j.src.group; name = $j.src.name; url = $j.src.url; ttfb = $r.ttfb; codec = $r.codec }
        }
        $j.ps.Dispose()
    }
    $pool.Close()
    return ($out | Sort-Object ttfb)
}

function Write-M3u($path, $rows) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('#EXTM3U')
    foreach ($r in $rows) {
        $n = $r.name -replace '"', ''
        [void]$sb.AppendLine(('#EXTINF:-1 tvg-name="{0}" group-title="{1}",{2}' -f $n, $r.group, $r.name))
        [void]$sb.AppendLine($r.url)
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("wrote " + $path + " rows=" + $rows.Count)
}

# group names
$gStar = Str @(0x660E,0x661F,0x4E13,0x573A)
$gMovie = Str @(0x5F71,0x89C6,0x5267)
$gOther = Str @(0x5176,0x4ED6,0x8F6E,0x64AD)
$gH265 = (Str @(0x48,0x2E,0x32,0x36,0x35)) + '-' + (Str @(0x9ED1,0x5C4F,0x9700,0x6362,0x89E3,0x7801))
$jUser = Str @(0x7528,0x6237)
$jLive = Str @(0x6B63,0x5728,0x76F4,0x64AD)
$jTest = Str @(0x6D4B,0x8BD5)

$starAliases = @(
    @((Str @(0x5218,0x5FB7,0x534E)), (Str @(0x534E,0x4ED4))),
    @((Str @(0x6797,0x6B63,0x82F1)), (Str @(0x4E5D,0x53D4))),
    @((Str @(0x5468,0x661F,0x9A70)), (Str @(0x661F,0x7237))),
    @((Str @(0x6210,0x9F99))),
    @((Str @(0x5468,0x6DA6,0x53D1)), (Str @(0x53D1,0x54E5))),
    @((Str @(0x674E,0x8FDE,0x6770))),
    @((Str @(0x6D2A,0x91D1,0x5B9D))),
    @((Str @(0x7504,0x5B50,0x4E39))),
    @((Str @(0x5F20,0x56FD,0x8363))),
    @((Str @(0x53E4,0x5929,0x4E50))),
    @((Str @(0x6881,0x671D,0x4F1F))),
    @((Str @(0x5F20,0x536B,0x5065)))
)

$movieKeys = @(
    (Str @(0x7535,0x5F71)), (Str @(0x5267)), (Str @(0x7ECF,0x5178)),
    (Str @(0x7247)), (Str @(0x6E2F)), (Str @(0x5408,0x96C6)),
    (Str @(0x7CFB,0x5217)), (Str @(0x9AD8,0x6E05))
)

$nChow = Str @(0x5468,0x6DA6,0x53D1)
$nMovie = Str @(0x7535,0x5F71)
$nBak = Str @(0x5907,0x7528)
$nAndy = Str @(0x5218,0x5FB7,0x534E)
$nGu = Str @(0x53E4,0x5929,0x4E50)
$nLiang = Str @(0x6881,0x671D,0x4F1F)
$nZhang = Str @(0x5F20,0x536B,0x5065)
$nLu = Str @(0x9E7F,0x9F0E,0x8BB0)
$nXi = Str @(0x897F,0x6E38,0x8BB0)
$gPreferred = Str @(0x7CBE,0x9009)
$gSatellite = Str @(0x536B,0x89C6)
$gCCTV = Str @(0x592E,0x89C6)

# pinned star channels (not part of the public rotation list)
$pinned = @(
    [pscustomobject]@{ group = $gStar; name = $nAndy; url = 'http://1.14.124.206:35455/huya/11342424' },
    [pscustomobject]@{ group = $gStar; name = ($nAndy + '-' + $nBak + '1'); url = 'http://8.155.43.98:35455/huya/11342424' },
    [pscustomobject]@{ group = $gStar; name = ($nAndy + '-' + $nBak + '2'); url = 'https://live.metshop.top/huya/11342424' },
    [pscustomobject]@{ group = $gStar; name = ($nChow + $nMovie); url = 'http://198.204.228.26/live/lbzrf.m3u8' },
    [pscustomobject]@{ group = $gStar; name = ($nChow + $nMovie + '-' + $nBak); url = 'http://107.150.60.122/live/lbzrf.m3u8' },
    [pscustomobject]@{ group = $gStar; name = $nGu; url = 'http://1.14.124.206:35455/huya/11602041' },
    [pscustomobject]@{ group = $gStar; name = ($nLiang + '-' + $nLu); url = 'http://1.14.124.206:35455/huya/23734183' },
    [pscustomobject]@{ group = $gStar; name = ($nZhang + '-' + $nXi); url = 'http://1.14.124.206:35455/huya/23728660' }
)

# ---------- HD: IPTV unicast, Heilongjiang ----------
$hdUrl = 'https://raw.githubusercontent.com/xisohi/CHINA-IPTV/main/Unicast/heilongjiang/mobile.txt'
$hdText = Fetch-Text $hdUrl
if ($hdText) {
    $hd = Parse-Entries $hdText
    $genre = @{}
    $cur = $gOther
    foreach ($l in ($hdText -split "\r?\n|\r")) {
        $t = $l.Trim()
        if ($t -match '^(.*),#genre#$') { $cur = $matches[1]; continue }
        if ($t -match '^([^,]+),(https?://\S+)$') { $genre[$matches[2].Trim()] = $cur }
    }
    foreach ($e in $hd) { if ($genre.ContainsKey($e.url)) { $e.group = $genre[$e.url] } }
    $hdOk = @(Test-List $hd 8)
    Write-Host ("hd candidates=" + $hd.Count + " alive=" + $hdOk.Count)
    if ($hdOk.Count -gt 0) { Write-M3u (Join-Path $root 'hd.m3u') $hdOk }
} else {
    Write-Host 'hd source unreachable, skipping hd.m3u'
}

# ---------- rotation ----------
$pinnedOk = @(Test-List $pinned 8)
Write-Host ("pinned alive=" + $pinnedOk.Count)

$lbText = Fetch-Text 'https://sub.ottiptv.cc/yylunbo.m3u'
$lbOk = @()
if ($lbText) {
    $lb = Parse-Entries $lbText
    $seen = @{}
    $cand = @()
    foreach ($e in $lb) {
        if ($seen.ContainsKey($e.url)) { continue }
        $seen[$e.url] = 1
        if ($e.name -match '^\d{4}-\d{2}-\d{2}') { continue }
        if ($e.name.Contains($jUser)) { continue }
        if ($e.name.Contains($jLive)) { continue }
        if ($e.name.Contains($jTest)) { continue }
        $cand += $e
    }
    $lbOk = @(Test-List $cand 10)
    Write-Host ("rotation candidates=" + $cand.Count + " alive=" + $lbOk.Count)
}

$all = @($pinnedOk) + @($lbOk)
if ($all.Count -gt 0) {
    $hevc = @($all | Where-Object { $_.codec -eq 'HEVC' })
    $play = @($all | Where-Object { $_.codec -ne 'HEVC' })

    $starRows = @()
    $starSeen = @{}
    foreach ($aliases in $starAliases) {
        foreach ($r in $play) {
            $hit = $false
            foreach ($a in $aliases) { if ($r.name.Contains($a)) { $hit = $true; break } }
            if (-not $hit) { continue }
            if ($starSeen.ContainsKey($r.url)) { continue }
            $starSeen[$r.url] = 1
            $starRows += $r
        }
    }
    $movieRows = @()
    $otherRows = @()
    foreach ($r in $play) {
        if ($starSeen.ContainsKey($r.url)) { continue }
        $isMovie = $false
        foreach ($k in $movieKeys) { if ($r.name.Contains($k)) { $isMovie = $true; break } }
        if ($isMovie) { $movieRows += $r } else { $otherRows += $r }
    }

    $rows = @()
    foreach ($r in $starRows) { $rows += [pscustomobject]@{ group = $gStar; name = $r.name; url = $r.url } }
    foreach ($r in $movieRows) { $rows += [pscustomobject]@{ group = $gMovie; name = $r.name; url = $r.url } }
    foreach ($r in $otherRows) { $rows += [pscustomobject]@{ group = $gOther; name = $r.name; url = $r.url } }
    foreach ($r in $hevc) { $rows += [pscustomobject]@{ group = $gH265; name = $r.name; url = $r.url } }

    Write-M3u (Join-Path $root 'lunbo.m3u') $rows
    Write-Host ("star=" + $starRows.Count + " movie=" + $movieRows.Count + " other=" + $otherRows.Count + " hevc=" + $hevc.Count)
} else {
    Write-Host 'rotation refresh produced nothing, leaving lunbo.m3u untouched'
}
