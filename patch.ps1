# 0. 게임과 런쳐를 끕니다
# 1. 우상단의 Raw 버튼을 눌러서 game/ 폴더 안에다 이 스크립트를 저장하세요
# 2. 우클릭 - Powershell로 실행
#    스크립트가 게임 파일이 깨졌는지 확인하고, 깨진 파일을 별도 폴더에 다시 다운로드합니다
# 3. game/ 옆에 있는 별도 폴더 (game-버전명) 내용물을 game 폴더 안에 덮어쓰세요
# 4. 2-3번 반복
# 5. 아무것도 다운받지 않으면 아무 문제 없습니다
#
# 실시간 진행률 표시 + 병렬 다운로드

param (
    [string]$WorkingDirectory,
    [int]$Parallel = 16
)

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        $CurrentDirectory = $PWD.Path
        $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + 
                      "-WorkingDirectory `"$CurrentDirectory`" " +
                      "-Parallel $Parallel " +
                      $MyInvocation.UnboundArguments
        
        Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
        Exit
    }
}

if ($WorkingDirectory) {
    Set-Location -Path $WorkingDirectory
    Write-Host "Working Directory: $WorkingDirectory"
}

# Get JSON data
$JSON = Invoke-RestMethod -Uri "http://fcdp.ff14.co.kr/FileListGame.json"

$VERSION = $JSON.Version
$BASE_URL = $JSON.URL

Write-Host "Version: $VERSION"
Write-Host "Base URL: $BASE_URL"
Write-Host "Parallel Download: $Parallel threads"
Write-Host ""

function Test-FileIntegrity {
    param (
        [string]$Path,
        [long]$ExpectedSize,
        [string]$ExpectedHash
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    $actualSize = (Get-Item $Path).Length
    if ($ExpectedSize -ne $actualSize) {
        return $false
    }

    $actualHash = (Get-FileHash -Path $Path -Algorithm MD5).Hash.ToLower()
    if ($ExpectedHash -ne $actualHash) {
        return $false
    }

    return $true
}

function Format-FileSize {
    param([long]$Bytes)
    
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

function Get-ProgressBar {
    param(
        [int]$Percent,
        [int]$Width = 20
    )
    
    $filled = [math]::Floor($Width * $Percent / 100)
    $empty = $Width - $filled
    
    $bar = ""
    $bar += "█" * $filled
    $bar += "░" * $empty
    
    return $bar
}

# ============================================================================
# 1단계: 파일 검사
# ============================================================================

Write-Host "=== Step 1: Checking files ===" -ForegroundColor Cyan
$downloadList = @()

$totalFiles = $JSON.FileList.Count
$checkedCount = 0
$corruptCount = 0

foreach ($file in $JSON.FileList) {
    $path = $file.Name
    $size = $file.Size
    $hash = $file.CheckSum.ToLower()

    if ($path -eq "nvngx_dlss.dll") {
        $checkedCount++
        continue
    }

    $checkedCount++
    $percent = [math]::Floor(($checkedCount / $totalFiles) * 100)
    $progressBar = Get-ProgressBar -Percent $percent -Width 30
    $statusLine = "`rChecking: $progressBar {0,3}% ({1}/{2}) | Corrupt: {3}" -f $percent, $checkedCount, $totalFiles, $corruptCount
    Write-Host $statusLine -NoNewline

    if (-not (Test-FileIntegrity -Path ".\$path" -ExpectedSize $size -ExpectedHash $hash)) {
        $corruptCount++
        $downloadList += @{
            Name = $path
            Size = $size
            Hash = $hash
            Url = "$BASE_URL$path"
            ShortName = Split-Path -Path $path -Leaf
        }
    }
}

Write-Host ""
Write-Host "Check complete: $totalFiles files scanned, $corruptCount corrupted." -ForegroundColor Green

if ($downloadList.Count -eq 0) {
    Write-Host "`n=== All files are OK! ===" -ForegroundColor Green
    exit 0
}

$totalSize = ($downloadList | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
$totalSizeGB = [math]::Round($totalSize / 1GB, 2)

Write-Host "`n=== Step 2: Downloading files ===" -ForegroundColor Cyan
Write-Host "Files to download: $($downloadList.Count)" -ForegroundColor Yellow
Write-Host "Total size: $totalSizeGB GB" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# 2단계: 병렬 다운로드 + 실시간 진행률 (동시에!)
# ============================================================================

$jobs = @{}
$downloadStates = @{}
$completed = 0
$failed = @()
$startTime = Get-Date
$nextJobIndex = 0

$jobs = @{}
$downloadStates = @{}
$completed = 0
$failed = @()
$startTime = Get-Date
$nextJobIndex = 0

$maxDisplay = [math]::Min($Parallel, 15)

# 메인 루프: Job 시작 + 모니터링 동시 수행
while ($completed -lt $downloadList.Count) {
    # 1. 새 Job 시작 (동시 실행 제한)
    while ($nextJobIndex -lt $downloadList.Count -and (Get-Job -State Running).Count -lt $Parallel) {
        $item = $downloadList[$nextJobIndex]
        $targetPath = Join-Path -Path "..\game-$VERSION" -ChildPath $item.Name
        $targetDir = Split-Path -Path $targetPath -Parent
        
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        $job = Start-Job -ScriptBlock {
            param($Url, $OutputPath, $ExpectedSize, $ExpectedHash)
            
            function Test-FileIntegrity {
                param($Path, $ExpectedSize, $ExpectedHash)
                if (-not (Test-Path $Path)) { return $false }
                $actualSize = (Get-Item $Path).Length
                if ($ExpectedSize -ne $actualSize) { return $false }
                $actualHash = (Get-FileHash -Path $Path -Algorithm MD5).Hash.ToLower()
                return ($actualHash -eq $ExpectedHash)
            }
            
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
                
                if (Test-FileIntegrity -Path $OutputPath -ExpectedSize $ExpectedSize -ExpectedHash $ExpectedHash) {
                    return @{ Success = $true }
                }
                else {
                    Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                    return @{ Success = $false; Error = "Integrity check failed" }
                }
            }
            catch {
                if (Test-Path $OutputPath) {
                    Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                }
                return @{ Success = $false; Error = $_.Exception.Message }
            }
        } -ArgumentList @($item.Url, $targetPath, $item.Size, $item.Hash)
        
        $jobs[$nextJobIndex] = @{
            Job = $job
            Item = $item
            TargetPath = $targetPath
            Index = $nextJobIndex
            StartTime = Get-Date
        }
        
        $downloadStates[$nextJobIndex] = @{
            Name = $item.ShortName
            Size = $item.Size
            CurrentSize = 0
            Percent = 0
            Status = "Downloading"
            Speed = 0
            Path = $targetPath
        }
        
        $nextJobIndex++
    }
    
    # 2. 화면 업데이트 (실시간 진행률)
    Clear-Host
    
    # 헤더 다시 출력
    Write-Host "=== Downloading ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 활성 Job들의 진행률 표시
    $activeJobs = $jobs.Values | Where-Object { $_.Job.State -eq "Running" }
    $displayJobs = $activeJobs | Select-Object -First $maxDisplay
    
    foreach ($jobInfo in $displayJobs) {
        $state = $downloadStates[$jobInfo.Index]
        
        # 파일 크기 체크
        if (Test-Path $jobInfo.TargetPath) {
            $currentSize = (Get-Item $jobInfo.TargetPath).Length
            $state.CurrentSize = $currentSize
            
            if ($state.Size -gt 0) {
                $state.Percent = [math]::Min([math]::Floor(($currentSize / $state.Size) * 100), 99)
            }
            
            # 속도 계산
            $elapsed = ((Get-Date) - $jobInfo.StartTime).TotalSeconds
            if ($elapsed -gt 0 -and $currentSize -gt 0) {
                $state.Speed = [math]::Round(($currentSize / $elapsed) / 1MB, 2)
            }
        }
        
        # 진행률 바 생성
        $progressBar = Get-ProgressBar -Percent $state.Percent -Width 20
        $sizeStr = "{0}/{1}" -f (Format-FileSize $state.CurrentSize), (Format-FileSize $state.Size)
        
        # 파일명 길이 제한
        $displayName = $state.Name
        if ($displayName.Length -gt 30) {
            $displayName = $displayName.Substring(0, 27) + "..."
        }
        
        # 한 줄 출력
        $line = "[{0:D2}] {1,-33} {2} {3,3}% {4,15} {5,8} MB/s" -f `
            $jobInfo.Index,
            $displayName,
            $progressBar,
            $state.Percent,
            $sizeStr,
            $state.Speed
        
        Write-Host $line
    }
    
    # 요약 정보
    $totalElapsed = ((Get-Date) - $startTime).TotalSeconds
    $totalDownloaded = ($downloadStates.Values | Measure-Object -Property CurrentSize -Sum).Sum
    $avgSpeed = if ($totalElapsed -gt 0) { 
        [math]::Round(($totalDownloaded / $totalElapsed) / 1MB, 2) 
    } else { 0 }
    
    Write-Host ""
    Write-Host ("━" * 80) -ForegroundColor DarkGray
    Write-Host ("Progress: {0}/{1} completed | Queue: {2} waiting | Active: {3}/{4} | Speed: {5} MB/s" -f `
        $completed, $downloadList.Count, ($downloadList.Count - $nextJobIndex), 
        $activeJobs.Count, $Parallel, $avgSpeed) -ForegroundColor Yellow
    
    # 3. 완료된 Job 처리
    $completedJobs = $jobs.Values | Where-Object { $_.Job.State -eq "Completed" }
    foreach ($jobInfo in $completedJobs) {
        $result = Receive-Job -Job $jobInfo.Job
        Remove-Job -Job $jobInfo.Job
        
        $state = $downloadStates[$jobInfo.Index]
        
        if ($result.Success) {
            $state.Status = "Completed"
            $state.Percent = 100
            $state.CurrentSize = $state.Size
        }
        else {
            $state.Status = "Failed"
            $failed += @{ Name = $jobInfo.Item.Name; Error = $result.Error }
        }
        
        $completed++
        $jobs.Remove($jobInfo.Index)
    }
    
    Start-Sleep -Milliseconds 500
}

# 최종 정리
Get-Job | Remove-Job -Force

# ============================================================================
# 3단계: 결과 요약
# ============================================================================

Clear-Host

Write-Host "`n=== Download Complete ===" -ForegroundColor Cyan
Write-Host "Success: $($downloadList.Count - $failed.Count)/$($downloadList.Count)" -ForegroundColor Green

if ($failed.Count -gt 0) {
    Write-Host "`nFailed files:" -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host "  - $($f.Name): $($f.Error)" -ForegroundColor Red
    }
    Write-Host "`nYou can run this script again to retry failed downloads." -ForegroundColor Yellow
}

Write-Host "`nDownloaded files location: ..\game-$VERSION" -ForegroundColor Yellow
Write-Host "Please copy contents to game folder and overwrite." -ForegroundColor Yellow
