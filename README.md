# FFXIV 고속 파일 복구 도구

파이널 판타지 XIV 한국 서버의 손상되거나 누락된 게임 파일을 **실시간 진행률 표시**와 함께 **병렬 다운로드**로 빠르게 복구하는 PowerShell 스크립트입니다.
Claude Code로 작성되었습니다.

## 사전 요구사항

- Windows 10 이상
- 관리자 권한
- 인터넷 연결

## 설치 방법

### 1. PowerShell 7 설치 (없다면)

```powershell

winget install Microsoft.PowerShell

```

### 2. 실행 정책 설정

```powershell

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

```

### 3. 스크립트 파일 차단 해제

스크립트를 다운로드한 후, 게임 폴더(`game/`)에 저장하고 다음 명령어를 실행:

```powershell

Unblock-File .\patch.ps1

```

## 🚀 사용 방법

### 기본 사용

1. **게임과 런처를 종료**합니다
2. 게임 폴더(`game/`)로 이동합니다
3. 스크립트를 실행합니다:

```powershell
pwsh .\patch.ps1
```

### 고급 옵션

**더 빠른 다운로드 (예 : 16개 동시 다운로드):**

```powershell
pwsh .\patch.ps1 -Parallel 16
```

## 📺 실행 화면 예시

```
=== Downloading ===

[01] 020501.win32.dat0          ████████████░░░░░░░░ 60%  2.1GB/3.6GB   45.2 MB/s
[02] 00008.bk2                  ██████████████░░░░░░ 72%  280MB/387MB   38.4 MB/s
[03] ffxiv_dx11.exe             ████░░░░░░░░░░░░░░░░ 20%   10MB/50MB    12.3 MB/s
[04] 030500.win32.dat0          ██████░░░░░░░░░░░░░░ 31%  650MB/2.1GB   51.2 MB/s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Progress: 15/224 completed | Queue: 200 waiting | Active: 4/8 | Speed: 54.88 MB/s
```

## 📝 작동 원리

1. **파일 검사 단계**

   - 서버에서 최신 파일 목록(`FileListGame.json`) 다운로드
   - 로컬 파일의 크기 및 MD5 해시 검증
   - 손상되거나 누락된 파일 목록 생성

2. **병렬 다운로드 단계**

   - 손상된 파일만 선별적으로 다운로드
   - 여러 파일을 동시에 다운로드 (기본 8개)
   - 0.5초마다 실시간 진행률 업데이트

3. **파일 적용 단계**
   - 다운로드된 파일은 `game-버전명` 폴더에 저장
   - 사용자가 직접 `game` 폴더로 복사하여 적용

## ⚠️ 주의사항

- 스크립트는 **마이너 패치/핫픽스가 적용되지 않은** 기본 버전 파일을 가져옵니다
- 핫픽스가 적용된 상태에서 실행하면 핫픽스가 제거될 수 있습니다
- `nvngx_dlss.dll` (NVIDIA DLSS) 파일은 검사에서 제외됩니다
- 다운로드 속도는 네트워크 환경에 따라 다를 수 있습니다

## 🔄 파일 적용 방법

다운로드가 완료되면:

1. `game` 폴더 옆에 생성된 `game-버전명` 폴더를 엽니다
2. 내용물을 **전체 선택**합니다
3. `game` 폴더에 **복사**하여 덮어씁니다
4. 덮어쓰기 확인 시 **모두 바꾸기**를 선택합니다

## 🐛 문제 해결

### "실행 정책" 오류가 발생하는 경우

```powershell
pwsh -ExecutionPolicy Bypass .\patch-realtime-fixed.ps1
```

### 다운로드가 실패한 경우

스크립트를 다시 실행하면 **실패한 파일만** 재다운로드됩니다.

### 진행률이 표시되지 않는 경우

- PowerShell 7이 설치되어 있는지 확인하세요
- PowerShell 5.1에서는 성능이 저하되고 진행률 표시가 다를 수 있습니다

## 📄 라이선스

이 스크립트는 교육 및 개인 사용 목적으로 제공됩니다. 게임 파일 자체는 Square Enix의 지적 재산입니다.

## 🙋 FAQ

**Q: 공식 런처를 대체할 수 있나요?**  
A: 아니요. 이 도구는 **파일 복구 전용**입니다. 정상적인 게임 업데이트는 공식 런처를 사용하세요.

**Q: 안전한가요?**  
A: 공식 한국 서버(`fcdp.ff14.co.kr`)에서 파일을 다운로드하며, 별도 폴더에 저장 후 수동으로 복사하므로 안전합니다.

**Q: 모든 파일을 강제로 다시 받고 싶어요**  
A: `-Force` 옵션을 추가하세요 (현재 버전에는 미구현)

---

**⚡ 빠른 시작:**

```powershell
winget install Microsoft.PowerShell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Unblock-File .\patch-realtime-fixed.ps1
pwsh .\patch-realtime-fixed.ps1
```
