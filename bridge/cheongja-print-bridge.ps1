# 청자다방 포스기 인쇄 브리지 (v2 — byte-safe + 자동 업데이트)
# BIXOLON SRP-330II (COM3, 9600 8N1) 직결 ESC/POS 송신.
# localhost:18080 에 HTTP 서버. /print, /test, /health, /version.
#
# v2 변경점:
#   - 한글 라벨을 CP949 byte 시퀀스로 inline 작성 (ps1 파일 인코딩 무관 안정 출력)
#   - 30분마다 GitHub Pages 에서 새 버전 자동 다운로드 + 교체 + 재시작
#   - 이후로는 사장님이 USB 옮길 필요 없음. web 측 deploy.sh 만 돌리면 매장 PC 가 알아서 업데이트

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$VERSION = '2.0.0'

# ---------------------------------------------------------------------------
# 설정 (config.json 으로 덮어쓰기 가능)
# ---------------------------------------------------------------------------
$defaults = @{
  port           = 'COM3'
  baud           = 9600
  httpPort       = 18080
  paperWidth     = 48
  cutPaper       = $true
  drawerKick     = $false
  beep           = $false
  copies         = 1
  autoUpdate     = $true
  updateUrl      = 'https://mlnyx.github.io/cheongja-menu-site/bridge/cheongja-print-bridge.ps1'
  updateCheckMin = 30
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'config.json'
$logDir = Join-Path $env:LOCALAPPDATA 'cheongja-pos\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir ("bridge-" + (Get-Date -Format 'yyyyMMdd') + '.log')

function Write-Log {
  param([string]$Level, [string]$Message)
  $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
  try { Add-Content -Path $logPath -Value $line -Encoding UTF8 } catch {}
  Write-Host $line
}

$config = $defaults.Clone()
if (Test-Path $configPath) {
  try {
    $userConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $userConfig.PSObject.Properties) {
      $config[$prop.Name] = $prop.Value
    }
    Write-Log 'INFO' "config.json 로드 완료"
  } catch {
    Write-Log 'WARN' "config.json 파싱 실패, 기본값 사용: $_"
  }
}

Write-Log 'INFO' "브리지 v$VERSION 시작 준비 (printer=$($config.port), baud=$($config.baud), autoUpdate=$($config.autoUpdate))"

# ---------------------------------------------------------------------------
# 한글 라벨 — CP949 byte 시퀀스 (ps1 파일 인코딩과 무관하게 안정 출력)
# ---------------------------------------------------------------------------
$KR = @{
  CHEONGJA       = [byte[]]@(0xc3, 0xbb, 0xc0, 0xda, 0xb4, 0xd9, 0xb9, 0xe6)
  PUNGAM         = [byte[]]@(0xc7, 0xb3, 0xbe, 0xcf, 0xc1, 0xa1)
  ORDER_NO       = [byte[]]@(0xc1, 0xd6, 0xb9, 0xae, 0xb9, 0xf8, 0xc8, 0xa3, 0x20)
  TABLE_LABEL    = [byte[]]@(0xb9, 0xf8, 0x20, 0xc5, 0xd7, 0xc0, 0xcc, 0xba, 0xed)
  TAKEOUT_LABEL  = [byte[]]@(0xc6, 0xf7, 0xc0, 0xe5, 0x20, 0xc1, 0xd6, 0xb9, 0xae)
  GUEST          = [byte[]]@(0xbc, 0xd5, 0xb4, 0xd4, 0x20, 0x20, 0x20, 0x20, 0x3a, 0x20)
  PHONE          = [byte[]]@(0xbf, 0xac, 0xb6, 0xf4, 0xc3, 0xb3, 0x20, 0x20, 0x3a, 0x20)
  PICKUP         = [byte[]]@(0xc7, 0xc8, 0xbe, 0xf7, 0x20, 0x20, 0x20, 0x20, 0x3a, 0x20)
  ORDER_TIME     = [byte[]]@(0xc1, 0xd6, 0xb9, 0xae, 0xbd, 0xc3, 0xb0, 0xa2, 0x3a, 0x20)
  MENU           = [byte[]]@(0xb8, 0xde, 0xb4, 0xba)
  TOTAL          = [byte[]]@(0xc7, 0xd5, 0xb0, 0xe8)
  PAY            = [byte[]]@(0xb0, 0xe1, 0xc1, 0xa6, 0x20, 0x20, 0x20, 0x20, 0x3a, 0x20)
  NOTE           = [byte[]]@(0xbf, 0xe4, 0xc3, 0xbb, 0xbb, 0xe7, 0xc7, 0xd7)
  MIN_AFTER      = [byte[]]@(0xba, 0xd0, 0x20, 0xc8, 0xc4)
  WON            = [byte[]]@(0xbf, 0xf8)
  ADDR           = [byte[]]@(0xb1, 0xa4, 0xc1, 0xd6, 0xb1, 0xa4, 0xbf, 0xaa, 0xbd, 0xc3, 0x20, 0xbc, 0xad, 0xb1, 0xb8, 0x20, 0xc7, 0xb3, 0xbe, 0xcf, 0xb5, 0xbf)
  PRINT_TEST     = [byte[]]@(0xc0, 0xce, 0xbc, 0xe2, 0x20, 0xc5, 0xd7, 0xbd, 0xba, 0xc6, 0xae)
  TIME_LABEL     = [byte[]]@(0xbd, 0xc3, 0xb0, 0xa2, 0x3a, 0x20)
  WORKING_OK     = [byte[]]@(0xc1, 0xa4, 0xbb, 0xf3, 0x20, 0xb5, 0xbf, 0xc0, 0xdb, 0xc7, 0xcf, 0xb0, 0xed, 0x20, 0xc0, 0xd6, 0xbd, 0xc0, 0xb4, 0xcf, 0xb4, 0xd9)
  BRIDGE_RUNNING = [byte[]]@(0xc6, 0xf7, 0xbd, 0xba, 0xb1, 0xe2, 0x20, 0xc0, 0xce, 0xbc, 0xe2, 0x20, 0xba, 0xea, 0xb8, 0xae, 0xc1, 0xf6, 0xb0, 0xa1)
  HANGUL_CHECK   = [byte[]]@(0xc7, 0xd1, 0xb1, 0xdb, 0x20, 0xc3, 0xe2, 0xb7, 0xc2, 0x20, 0xc8, 0xae, 0xc0, 0xce, 0x3a, 0x20, 0xb0, 0xa1, 0xb3, 0xaa, 0xb4, 0xd9, 0xb6, 0xf3, 0xb8, 0xb6, 0xb9, 0xd9, 0xbb, 0xe7, 0xbe, 0xc6, 0xc0, 0xda, 0xc2, 0xf7, 0xc4, 0xab, 0xc5, 0xb8, 0xc6, 0xc4, 0xc7, 0xcf)
}

# 동적 데이터 (JSON 으로 받은 한글) — CP949 인코더
$encKR = [System.Text.Encoding]::GetEncoding(949)

# ---------------------------------------------------------------------------
# ESC/POS 영수증 빌더
# ---------------------------------------------------------------------------
function Build-Receipt {
  param([hashtable]$Order, [int]$Width = 48)

  $bytes = New-Object System.Collections.Generic.List[byte]
  function Add-Bytes($arr) { foreach ($b in $arr) { $bytes.Add([byte]$b) } }
  function Add-Dyn($s) {
    if ($null -eq $s -or $s -eq '') { return }
    foreach ($b in $encKR.GetBytes($s)) { $bytes.Add($b) }
  }
  function Add-NL { Add-Bytes @(0x0A) }
  function Sep($ch = '-') { Add-Dyn ($ch * $Width); Add-NL }

  # 초기화 + 한글 모드
  Add-Bytes @(0x1B, 0x40)         # ESC @ initialize
  Add-Bytes @(0x1C, 0x26)         # FS & korean ON
  Add-Bytes @(0x1B, 0x74, 0x0D)   # ESC t 13 codepage KS5601 (BIXOLON)
  Add-Bytes @(0x1B, 0x52, 0x0D)   # ESC R 13 charset Korea
  Add-Bytes @(0x1B, 0x33, 0x24)   # 줄간격 36 dots

  # 헤더 (큰 글씨 center)
  Add-Bytes @(0x1B, 0x61, 0x01)               # center
  Add-Bytes @(0x1D, 0x21, 0x11)               # 2x size
  Add-Bytes $KR.CHEONGJA; Add-NL
  Add-Bytes @(0x1D, 0x21, 0x00)
  Add-Bytes $KR.PUNGAM; Add-NL
  Add-Bytes @(0x1B, 0x61, 0x00)               # left
  Sep '='

  # 주문번호 (큰 글씨)
  Add-Bytes @(0x1B, 0x61, 0x01)
  Add-Bytes @(0x1D, 0x21, 0x22)               # 3x size
  Add-Bytes $KR.ORDER_NO
  Add-Dyn $Order.orderNo
  Add-NL
  Add-Bytes @(0x1D, 0x21, 0x00)
  Add-Bytes @(0x1B, 0x61, 0x00)

  # 테이블/포장 박스 (큰 글씨 + inverse)
  if ($null -ne $Order.orderLocation) {
    $loc = $Order.orderLocation
    $isTable = ($loc.kind -eq 'table' -and $null -ne $loc.tableNo)
    $isTakeout = ($loc.kind -eq 'takeout')
    if ($isTable -or $isTakeout) {
      Sep '-'
      Add-Bytes @(0x1B, 0x61, 0x01)
      Add-Bytes @(0x1D, 0x21, 0x11)
      Add-Bytes @(0x1D, 0x42, 0x01)            # inverse ON
      Add-Bytes @(0x20)                        # [ 좌측 패딩
      if ($isTable) {
        Add-Dyn ([string]$loc.tableNo)
        Add-Bytes $KR.TABLE_LABEL              # "번 테이블"
      } else {
        Add-Bytes $KR.TAKEOUT_LABEL            # "포장 주문"
      }
      Add-Bytes @(0x20)                        # 우측 패딩
      Add-NL
      Add-Bytes @(0x1D, 0x42, 0x00)            # inverse OFF
      Add-Bytes @(0x1D, 0x21, 0x00)
      Add-Bytes @(0x1B, 0x61, 0x00)
    }
  }
  Sep '-'

  # 손님 정보
  if ($Order.customerName) {
    Add-Bytes $KR.GUEST
    Add-Dyn $Order.customerName
    Add-NL
  }
  if ($Order.customerPhone) {
    Add-Bytes $KR.PHONE
    Add-Dyn $Order.customerPhone
    Add-NL
  }
  if ($null -ne $Order.pickupMinutes -and [int]$Order.pickupMinutes -gt 0) {
    Add-Bytes $KR.PICKUP
    Add-Dyn ([string]$Order.pickupMinutes)
    Add-Bytes @(0x20)
    Add-Bytes $KR.MIN_AFTER
    Add-NL
  }
  if ($Order.createdAtKst) {
    Add-Bytes $KR.ORDER_TIME
    Add-Dyn $Order.createdAtKst
    Add-NL
  }
  Sep '-'

  # 메뉴 라벨
  Add-Bytes @(0x1B, 0x45, 0x01)               # bold ON
  Add-Bytes $KR.MENU; Add-NL
  Add-Bytes @(0x1B, 0x45, 0x00)               # bold OFF

  foreach ($it in $Order.items) {
    $opt = ''
    if ($it.options -eq 'hot') { $opt = ' [HOT]' }
    elseif ($it.options -eq 'ice') { $opt = ' [ICE]' }
    $head = ("{0}{1} x{2}" -f $it.name, $opt, $it.quantity)
    $price = ("{0:N0}" -f ($it.unitPriceKrw * $it.quantity))
    # 좌: 메뉴, 우: 금액 + 원
    $headBytes = $encKR.GetBytes($head)
    $priceBytes = $encKR.GetBytes($price)
    $pad = $Width - $headBytes.Length - $priceBytes.Length - 1  # -1 for 원
    if ($pad -lt 1) { $pad = 1 }
    foreach ($b in $headBytes) { $bytes.Add($b) }
    Add-Dyn (' ' * $pad)
    foreach ($b in $priceBytes) { $bytes.Add($b) }
    Add-Bytes $KR.WON
    Add-NL
  }
  Sep '-'

  # 합계 (큰 글씨 + bold)
  $totalStr = ("{0:N0}" -f $Order.totalKrw)
  $totalBytes = $encKR.GetBytes($totalStr)
  Add-Bytes @(0x1D, 0x21, 0x01)               # 2x height
  Add-Bytes @(0x1B, 0x45, 0x01)               # bold
  Add-Bytes $KR.TOTAL
  # 우측 정렬 padding
  $totalLen = $KR.TOTAL.Length + $totalBytes.Length + $KR.WON.Length
  $pad = ($Width / 2) - $totalLen
  if ($pad -lt 1) { $pad = 1 }
  Add-Dyn (' ' * $pad)
  foreach ($b in $totalBytes) { $bytes.Add($b) }
  Add-Bytes $KR.WON
  Add-NL
  Add-Bytes @(0x1B, 0x45, 0x00)
  Add-Bytes @(0x1D, 0x21, 0x00)

  # 결제 수단
  if ($Order.paymentMethod) {
    Add-Bytes $KR.PAY
    Add-Dyn $Order.paymentMethod
    Add-NL
  }

  # 요청사항
  if ($Order.requestNote) {
    Sep '-'
    Add-Bytes @(0x1B, 0x45, 0x01)
    Add-Bytes $KR.NOTE; Add-NL
    Add-Bytes @(0x1B, 0x45, 0x00)
    Add-Dyn $Order.requestNote
    Add-NL
  }

  Sep '='
  Add-Bytes @(0x1B, 0x61, 0x01)               # center
  Add-Bytes $KR.CHEONGJA; Add-Bytes @(0x20); Add-Bytes $KR.PUNGAM; Add-NL
  Add-Bytes $KR.ADDR; Add-NL
  Add-Bytes @(0x1B, 0x61, 0x00)

  Add-Bytes @(0x0A, 0x0A, 0x0A, 0x0A)
  return ,$bytes.ToArray()
}

function Build-TestReceipt {
  param([int]$Width = 48)
  $bytes = New-Object System.Collections.Generic.List[byte]
  function Add-Bytes($arr) { foreach ($b in $arr) { $bytes.Add([byte]$b) } }
  function Add-Dyn($s) { foreach ($b in $encKR.GetBytes($s)) { $bytes.Add($b) } }
  function Add-NL { Add-Bytes @(0x0A) }

  Add-Bytes @(0x1B, 0x40)
  Add-Bytes @(0x1C, 0x26)
  Add-Bytes @(0x1B, 0x74, 0x0D)
  Add-Bytes @(0x1B, 0x52, 0x0D)

  Add-Bytes @(0x1B, 0x61, 0x01)
  Add-Bytes @(0x1D, 0x21, 0x11)
  Add-Bytes $KR.PRINT_TEST; Add-NL
  Add-Bytes @(0x1D, 0x21, 0x00)
  Add-NL
  Add-Bytes $KR.TIME_LABEL
  Add-Dyn (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Add-NL
  Add-NL
  Add-Bytes $KR.CHEONGJA; Add-Bytes @(0x20); Add-Bytes $KR.BRIDGE_RUNNING; Add-NL
  Add-Bytes $KR.WORKING_OK; Add-NL
  Add-NL
  Add-Dyn ("v$VERSION  BIXOLON SRP-330II"); Add-NL
  Add-Bytes $KR.HANGUL_CHECK; Add-NL
  Add-Bytes @(0x1B, 0x61, 0x00)

  Add-Bytes @(0x0A, 0x0A, 0x0A, 0x0A)
  return ,$bytes.ToArray()
}

# ---------------------------------------------------------------------------
# COM 송신
# ---------------------------------------------------------------------------
function Send-ToPrinter {
  param([byte[]]$Payload)
  $portName = $config.port
  $baud     = [int]$config.baud
  $maxRetry = 3
  $lastErr  = $null
  for ($i = 1; $i -le $maxRetry; $i++) {
    $sp = $null
    try {
      $sp = New-Object System.IO.Ports.SerialPort($portName, $baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
      $sp.Handshake   = [System.IO.Ports.Handshake]::None
      $sp.ReadTimeout  = 1000
      $sp.WriteTimeout = 3000
      $sp.DtrEnable = $true
      $sp.RtsEnable = $true
      $sp.Open()
      $chunkSize = 256
      $offset = 0
      while ($offset -lt $Payload.Length) {
        $size = [Math]::Min($chunkSize, $Payload.Length - $offset)
        $sp.Write($Payload, $offset, $size)
        $offset += $size
        Start-Sleep -Milliseconds 20
      }
      if ($config.cutPaper) {
        Start-Sleep -Milliseconds 100
        $cut = [byte[]]@(0x1D, 0x56, 0x42, 0x00)
        $sp.Write($cut, 0, $cut.Length)
      }
      if ($config.beep) {
        $bp = [byte[]]@(0x1B, 0x42, 0x03, 0x05)
        $sp.Write($bp, 0, $bp.Length)
      }
      if ($config.drawerKick) {
        $kick = [byte[]]@(0x1B, 0x70, 0x00, 0x19, 0xFA)
        $sp.Write($kick, 0, $kick.Length)
      }
      Start-Sleep -Milliseconds 150
      $sp.Close()
      return @{ ok = $true; tried = $i }
    }
    catch {
      $lastErr = $_.Exception.Message
      Write-Log 'WARN' "송신 시도 $i 실패: $lastErr"
      try { if ($sp -and $sp.IsOpen) { $sp.Close() } } catch {}
      Start-Sleep -Milliseconds (300 * $i)
    }
  }
  return @{ ok = $false; tried = $maxRetry; error = $lastErr }
}

# ---------------------------------------------------------------------------
# 자동 업데이트
# ---------------------------------------------------------------------------
function Try-AutoUpdate {
  if (-not $config.autoUpdate) { return $false }
  $remoteUrl = [string]$config.updateUrl
  if (-not $remoteUrl) { return $false }
  $selfPath = Join-Path $scriptDir 'cheongja-print-bridge.ps1'
  $tempPath = "$selfPath.new"
  try {
    Invoke-WebRequest -Uri $remoteUrl -OutFile $tempPath -TimeoutSec 15 -UseBasicParsing
    if (-not (Test-Path $tempPath)) { return $false }
    $size = (Get-Item $tempPath).Length
    if ($size -lt 5000) {
      Write-Log 'WARN' "원격 ps1 크기 비정상 ($size bytes), 업데이트 취소"
      Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
      return $false
    }
    $newHash = (Get-FileHash $tempPath -Algorithm SHA256).Hash
    $oldHash = (Get-FileHash $selfPath -Algorithm SHA256).Hash
    if ($newHash -eq $oldHash) {
      Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
      return $false
    }
    Write-Log 'INFO' "새 버전 발견 ($newHash -> 교체 + 재시작)"
    Copy-Item $selfPath ("$selfPath.bak") -Force
    Move-Item $tempPath $selfPath -Force
    $vbsPath = Join-Path $scriptDir 'cheongja-print-bridge.vbs'
    if (Test-Path $vbsPath) {
      Start-Process 'wscript.exe' -ArgumentList ("`"$vbsPath`"")
    }
    Write-Log 'INFO' '자기 종료 (재시작은 vbs 가 담당)'
    Start-Sleep -Seconds 1
    [System.Environment]::Exit(0)
    return $true
  } catch {
    Write-Log 'WARN' "자동 업데이트 실패: $_"
    try { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue } catch {}
    return $false
  }
}

# ---------------------------------------------------------------------------
# 미니 HTTP 서버
# ---------------------------------------------------------------------------
$listener = $null
try {
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, [int]$config.httpPort)
  $listener.Start()
} catch {
  Write-Log 'ERROR' "포트 $($config.httpPort) 바인딩 실패: $_"
  exit 1
}

Write-Log 'INFO' "브리지 v$VERSION 가동 — http://localhost:$($config.httpPort)"

# 시작 시 자동 업데이트 1회 (잠시 후, 시작 직후 race condition 회피)
$startupUpdateAt = (Get-Date).AddSeconds(30)
$lastUpdateCheck = Get-Date

function Send-Response {
  param([System.Net.Sockets.NetworkStream]$Stream, [int]$Status = 200,
        [string]$Body = '', [string]$ContentType = 'application/json; charset=utf-8')
  $reason = switch ($Status) { 200 {'OK'} 204 {'No Content'} 400 {'Bad Request'} 404 {'Not Found'} 405 {'Method Not Allowed'} 500 {'Internal Server Error'} default {'OK'} }
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $header = "HTTP/1.1 $Status $reason`r`n" +
            "Content-Type: $ContentType`r`n" +
            "Content-Length: $($bodyBytes.Length)`r`n" +
            "Access-Control-Allow-Origin: *`r`n" +
            "Access-Control-Allow-Methods: GET,POST,OPTIONS`r`n" +
            "Access-Control-Allow-Headers: Content-Type`r`n" +
            "Connection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($bodyBytes.Length -gt 0) {
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
  }
  $Stream.Flush()
}

function Read-Request {
  param([System.Net.Sockets.NetworkStream]$Stream)
  $buf = New-Object byte[] 16384
  $sb = New-Object System.Text.StringBuilder
  $headerEnd = -1
  $contentLength = 0
  while ($headerEnd -lt 0) {
    if (-not $Stream.DataAvailable -and $sb.Length -eq 0) {
      Start-Sleep -Milliseconds 10
    }
    $n = $Stream.Read($buf, 0, $buf.Length)
    if ($n -le 0) { break }
    [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buf, 0, $n))
    $headerEnd = $sb.ToString().IndexOf("`r`n`r`n")
    if ($sb.Length -gt 32768) { break }
  }
  if ($headerEnd -lt 0) { return $null }
  $headerPart = $sb.ToString().Substring(0, $headerEnd)
  $rest = $sb.ToString().Substring($headerEnd + 4)
  $lines = $headerPart -split "`r`n"
  $reqLine = $lines[0] -split ' '
  if ($reqLine.Length -lt 2) { return $null }
  $method = $reqLine[0]
  $path   = $reqLine[1]
  foreach ($h in $lines[1..($lines.Length - 1)]) {
    if ($h -match '^Content-Length:\s*(\d+)') {
      $contentLength = [int]$Matches[1]
    }
  }
  $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($rest)
  if ($bodyBytes.Length -lt $contentLength) {
    $remaining = $contentLength - $bodyBytes.Length
    $bodyBuf = New-Object byte[] $remaining
    $read = 0
    while ($read -lt $remaining) {
      $n = $Stream.Read($bodyBuf, $read, $remaining - $read)
      if ($n -le 0) { break }
      $read += $n
    }
    if ($read -gt 0) {
      $bodyBytes = $bodyBytes + $bodyBuf[0..($read - 1)]
    }
  } elseif ($bodyBytes.Length -gt $contentLength) {
    $bodyBytes = $bodyBytes[0..($contentLength - 1)]
  }
  $body = if ($bodyBytes.Length -gt 0) {
    [System.Text.Encoding]::UTF8.GetString($bodyBytes)
  } else { '' }
  return @{ Method = $method; Path = $path; Body = $body }
}

# ---------------------------------------------------------------------------
# 메인 루프 (Pending polling 으로 업데이트 체크 가능)
# ---------------------------------------------------------------------------
while ($true) {
  try {
    # 시작 후 30초 / 30분마다 자동 업데이트 체크
    $now = Get-Date
    if (($startupUpdateAt -ne $null -and $now -gt $startupUpdateAt) -or
        ($now - $lastUpdateCheck).TotalMinutes -gt [int]$config.updateCheckMin) {
      Try-AutoUpdate | Out-Null   # 새 버전이면 Exit, 아니면 false 반환
      $lastUpdateCheck = $now
      $startupUpdateAt = $null
    }

    if (-not $listener.Pending()) {
      Start-Sleep -Milliseconds 200
      continue
    }

    $client = $listener.AcceptTcpClient()
    $client.ReceiveTimeout = 5000
    $client.SendTimeout = 5000
    $stream = $client.GetStream()
    $req = Read-Request -Stream $stream
    if ($null -eq $req) { $client.Close(); continue }
    if ($req.Method -eq 'OPTIONS') {
      Send-Response -Stream $stream -Status 204
      $client.Close(); continue
    }
    Write-Log 'INFO' "$($req.Method) $($req.Path)"
    switch -Regex ($req.Path) {
      '^/health' {
        $info = @{
          ok = $true
          bridge = '청자다방 인쇄 브리지'
          version = $VERSION
          port = $config.port
          baud = $config.baud
          time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        } | ConvertTo-Json -Compress
        Send-Response -Stream $stream -Status 200 -Body $info
        break
      }
      '^/version' {
        $info = @{ version = $VERSION; autoUpdate = $config.autoUpdate; updateUrl = $config.updateUrl } | ConvertTo-Json -Compress
        Send-Response -Stream $stream -Status 200 -Body $info
        break
      }
      '^/update' {
        # 강제 업데이트 트리거 (POS 페이지에서 수동 호출 가능)
        $r = Try-AutoUpdate
        Send-Response -Stream $stream -Status 200 -Body (@{ ok = $true; updated = $r } | ConvertTo-Json -Compress)
        break
      }
      '^/test' {
        $payload = Build-TestReceipt -Width ([int]$config.paperWidth)
        $r = Send-ToPrinter -Payload $payload
        $body = ($r | ConvertTo-Json -Compress)
        Send-Response -Stream $stream -Status $(if ($r.ok) { 200 } else { 500 }) -Body $body
        break
      }
      '^/print' {
        if ($req.Method -ne 'POST') {
          Send-Response -Stream $stream -Status 405 -Body '{"ok":false,"error":"POST only"}'
          break
        }
        try {
          $order = $req.Body | ConvertFrom-Json
          $ht = @{
            orderNo       = $order.orderNo
            customerName  = $order.customerName
            customerPhone = $order.customerPhone
            pickupMinutes = $order.pickupMinutes
            createdAtKst  = $order.createdAtKst
            totalKrw      = [int]$order.totalKrw
            paymentMethod = $order.paymentMethod
            requestNote   = $order.requestNote
            orderLocation = $order.orderLocation
            items         = @()
          }
          foreach ($it in $order.items) {
            $ht.items += @{
              name          = $it.name
              quantity      = [int]$it.quantity
              unitPriceKrw  = [int]$it.unitPriceKrw
              options       = $it.options
            }
          }
          $copies = [int]$config.copies
          if ($copies -lt 1) { $copies = 1 }
          $lastResult = $null
          for ($c = 1; $c -le $copies; $c++) {
            $payload = Build-Receipt -Order $ht -Width ([int]$config.paperWidth)
            $lastResult = Send-ToPrinter -Payload $payload
            if (-not $lastResult.ok) { break }
            if ($c -lt $copies) { Start-Sleep -Milliseconds 300 }
          }
          $body = ($lastResult | ConvertTo-Json -Compress)
          Send-Response -Stream $stream -Status $(if ($lastResult.ok) { 200 } else { 500 }) -Body $body
        } catch {
          Write-Log 'ERROR' "/print 처리 실패: $_"
          Send-Response -Stream $stream -Status 400 -Body ("{`"ok`":false,`"error`":`"" + ($_.Exception.Message -replace '"','\"') + "`"}")
        }
        break
      }
      default {
        Send-Response -Stream $stream -Status 404 -Body '{"ok":false,"error":"not found"}'
      }
    }
    $client.Close()
  } catch {
    Write-Log 'ERROR' "요청 처리 예외: $_"
    try { if ($client) { $client.Close() } } catch {}
  }
}
