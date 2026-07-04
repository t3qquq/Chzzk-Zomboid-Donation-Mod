# 라스트오더 (LastOrder) — 좀보이드 B41 치지직 후원연동 시스템

**최종 업데이트**: 2026-07-05

---

## 📋 프로젝트 구조

### 1. **퍼펫 API** (`gui.py`)
- **상태**: 기능 완성 ✅ (t3 로컬 환경에서 구동 확인)
- 역할: 치지직 후원 이벤트 → `rewards.txt` 릴레이
- 기술: PyQt5 + chzzkpy (비공식) + asyncio
- 배포: PyInstaller `--onefile` → `PuppetAPI.exe`

### 2. **인게임 모드** (`t3chzzkDonation`, "[Puppet] chzzk API")
- **상태**: 인프라 완료, 18개 featureId 중 11개 구현 완료 / 7개 스텁
- 역할: `rewards.txt` 읽기 → 게임 이펙트 트리거 (히트맨 NPC, 폭격, 텔레포트, 좀비 룰렛, 스킬 물약 등)
- 기술: B41 Lua + 멀티플레이어 통신 (`sendClientCommand`, modData)
- 아키텍처: featureId 기반 디스패치 (`rewardManager.lua`)

---

## ✅ 완료된 작업

### 퍼펫 API (V2.2.4)
- ✅ Chzzk 채널 자동 해석 (URL / 채널명 / UUID)
- ✅ rewards.txt 경로 자동 탐지 + 수동 지정
- ✅ 도네 실시간 로깅 + 테스트 주입
- ✅ 리워드 티어 편집 UI
  - 금액 ↔ featureId 매핑 (표 형식)
  - 행 추가/삭제/저장
  - `reward_preset.json` 자동 export
- ✅ 리워드 프리셋 import
  - JSON 파일 불러오기 (체크리스트에서)
  - 다중 서버/스트리머용 티어 동기화 가능
  - 프리셋 존재 시 편집 UI 잠금 (초기화는 게이트에서만)
- ✅ 라인 포맷 (모드 규약): `amount,featureId,sender,message` (URL 인코딩)
- ✅ 19세 방송 감지 + 쿠키 지원 (네이버 NID)
- ✅ 런처 게이트 (화이트리스트 검증 → 방송/PZ/인게임 상태 체크 → 자동 연동)
- ✅ 감시 (MainGuard): PZ 종료 감지 + 19세 전환 감지 + 인게임 이탈 감지
- ✅ 단일 실행 exe 패키징 (`build.bat`, 아이콘 임베드)

### 인게임 모드 (V2.x)
- ✅ 리워드 수신 인프라
  - `DonationReceiver.lua`: 4필드 파싱 (`amount,featureId,sender,message`)
  - `rewardManager.lua`: featureId 기반 디스패치 (18개 슬롯)
- ✅ 히트맨 NPC 시스템 (Bandits 모드와 완전 네임스페이스 격리)
  - 히트맨 AI (`HitmanBrain`), `Sharpshooter`(발사 간격 단축) + `Berserker`(공격속도/타격률 가속) 전문성
  - Heartsight 탐지: Recon(+13) / Tracker(+53) 가산 적용
  - 플레이어/NPC 추적 (`GetTarget`)
  - modData 네임스페이싱 (충돌 방지)
- ✅ 폭격 시스템 (Bombard)
  - 서버 → 전체 브로드캐스트 → 각 클라이언트가 자신이 소유한 좀비만 킬 (B41 좀비 권한 모델 대응)
- ✅ 기능 구현 완료 (12개)
  - debuff_roulette / buff_roulette / zombie_roulette
  - sprinter5 / bandit_melee / vaccine / bandit_ranged / exile / missile / backroom
  - **random_skill_potion**: 시크릿 물약 7종 (`serum_supreme` + 근력/지구력/달리기/은신 등 미니 세럼 6종), 확률 디스패치 supreme 1% / strength 9% / fitness 10% / 나머지 20%씩 (`ZombRand(100)` 합 100 고정), `OnEat` 핸들러 `skillpotion.lua`로 통합
    - ⚠ 알려진 버그: `media/scripts/*.txt`에 `--`(Lua 스타일) 주석 잘못 사용 → 파서가 `serum_strength` 블록 통째로 스킵. `/* */`로 교체 필요 (아직 미수정)
  - **rise_up_dead_man** (신규): 도네 플레이어 반경 내 모든 시체(`IsoDeadBody`) 좀비로 부활
    - 클라: `riseup.lua` — 좌표/반경만 서버 전송 (시체는 서버 권한 객체이므로 부활도 서버 한 곳에서만 처리, 폭격과 권한 모델 정반대)
    - 서버: `server.lua`의 `DOServer["Schedule"]["RiseUp"]` — 반경 내 스퀘어 순회(0~7층) → `IsoDeadBody:reanimateNow()`
    - 현재 플레이어 시체도 구분 없이 부활 대상에 포함됨 (`isFakeDead()` 필터 미적용 — 의도적 방치, 원하면 필터 추가 가능)
    - 좀비였던 개체가 원래 스피드 타입(뛰좀 등) 유지한 채 부활하는지는 미확인 — 인게임 테스트 필요
- ✅ 샌드박스 옵션 (신규, `Hitmans_Donation` 페이지)
  - `Donation_BombardRadius` — 폭격 반경 (5~60타일, 기본 55)
  - `Donation_RiseUpRadius` — 부활 반경 (5~60타일, 기본 55, 폭격 반경과 완전 별개 변수)
  - `Donation_BombardDelay` — 폭격 발동 대기시간 (10~300초, 기본 60)
  - 전부 `SandboxVars.Hitmans` 사용 시점 읽기 (`SandboxVars and SandboxVars.Hitmans` nil 가드 패턴)

---

## 🚧 진행 중 / 남은 작업

### **A. 모드: 6개 featureId 스텁 구현** (우선순위 높음)

#### `rewardManager.lua`에 등록된 스텁 6개

| featureId | 라벨 | 설계 메모 | 의존성 | 추정 난이도 |
|-----------|------|---------|--------|-----------|
| `random_weapon` | 랜덤 무기 뽑기 | 티어별 무기 등급 확률 테이블 (예: 1000원→T1 낮음, 100000원→T3 높음) | 인벤토리 API | ⭐⭐ |
| `vehicle_kit` | 차량소환 키트 | `zone.a()` 안전지대 체크 재사용 + 차량 스폰 | 차량 API | ⭐⭐⭐ |
| `revive_ticket` | 즉시부활 티켓 | 기절 해제 (`immediate=true` 스텁만 등록) — 실제 구현 필요 | Status API | ⭐ |
| `cdda_spawn` | CDDA 스크리머/브루트 소환 | CDDA 모드 의존성 확인 후 | 외부 모드 | ⭐⭐⭐ |
| `secret_passage_kit` | 비밀통로 공사 키트 | `bombard.lua`의 `transmitAddObjectToSquare` 패턴 재사용 (벽 제거) | 맵 API | ⭐⭐⭐ |
| `horde_night` | 호드나이트 | 대량 좀비 스폰 + 서버 부하 관리 (스폰 큐 확장) | Spawn API | ⭐⭐⭐ |

**진행 전략**:
1. 난이도 ⭐부터 시작 (revive_ticket 제일 간단)
2. 각 구현 후 `luac5.1 -p` 문법 검증
3. B41 vanilla Lua 소스 참고:
   - `https://raw.githubusercontent.com/t3qquq/myPZ-Configs/refs/heads/main/pz41_lua_source.txt`
   - (bash_tool curl로 다운로드 후 grep/awk로 탐색, web_fetch 비권장 — 파일 크기)

---

### **B. 앱: `profits.txt` → xlsx 통계 스크립트** (우선순위 중간)

**배경**:
- `profits.txt` 형식: 한 줄당 `<streamer PZ 사용자명>\t<rewards.txt 한 줄>` (raw line = `amount,featureId,sender,message`), CRLF
- 클라이언트가 티어 유효성과 무관하게 **모든** 후원을 `sendClientCommand("DonationStats","Record",...)`로 전송, 호스트가 `player:getUsername()`으로 라벨링
- 시즌 종료 후 이 파일을 정리해 수익 리포트 생성

**요구사항**:
- 입력: `profits.txt`
- 출력: 4-sheet xlsx
  - **Sheet1 (Summary)**: 스트리머별 총 수익, 티어별 기여도
  - **Sheet2 (Daily)**: 날짜별 누적 수익 (시계열)
  - **Sheet3 (Top Donors)**: 상위 후원자 (sender별)
  - **Sheet4 (Raw)**: 전체 기록 (filters 포함)
- 기술: Python `openpyxl` 또는 `pandas` + `xlsxwriter`
- 스크립트: `stats_generator.py` (독립 실행 가능, cli 파라미터 받음)
- **상태**: 포맷 확정, 아직 미착수

**예상 코드량**: ~200–300 lines (읽기 + 파싱 + 표 생성)

---

### **C. 기타 개선 (낮은 우선순위)**

#### 퍼펫 API
- 🔄 Naver 자동 로그인 (19+ 시 PyQtWebEngine 임베드 웹뷰) — 비기술 사용자 UX 개선
- 🔄 코드 서명 (AV 경고 감소)

#### 모드
- `bandit.lua` NPC 킬 로직: 현재 클라이언트 사이드(`HitmanZombie.GetAll()`) — 서버사이드 Kaboom 핸들러로 이전 검토 중 (서버 컨텍스트에서 `HitmanZombie.GetAll()` 사용 가능 여부 확인 필요)
- 🗑 dead code cleanup ("나중에 다이어트"):
  - `rewardManager.lua` 큐 함수 (`.b` / `.c`)
  - `ManageSocialDistance` 호출
  - `HitmanMenu.lua` 스탈 메뉴 엔트리 (Looter / Companion)

---

## 🔧 개발 참조

### 소스 저장소
| 이름 | URL | 용도 |
|------|-----|------|
| PZ B41 Vanilla Lua | https://raw.githubusercontent.com/t3qquq/myPZ-Configs/refs/heads/main/pz41_lua_source.txt | 엔진 API 탐색 (bash_tool curl 권장) |
| 모드 소스 (최신) | https://github.com/t3qquq/Chzzk-Zomboid-Donation-Mod | featureId 구현 대상 |
| 앱 소스 | https://github.com/t3qquq/Chzzk-Zomboid-Donation-App | 티어/프리셋 UI |

### 빌드 / 배포
```bash
# 모드: Lua 문법 검증
luac5.1 -p t3chzzkDonation/media/lua/client/...lua

# 앱: exe 빌드
cd [퍼펫 API 폴더]
build.bat
# → dist/PuppetAPI.exe
```

### 테스트 서버
- **설정**: 로컬 싱글플레이 또는 localhost 멀티플레이
- **검증 포인트**:
  1. `rewards.txt` 라인 추가 확인
  2. 모드 콘솔 메시지 (DonationReceiver 파싱)
  3. 게임 이펙트 발동 (히트맨/폭격/텔레포트/스킬 물약 등)

---

## 📊 진행 요약

| 영역 | 완료율 | 비고 |
|------|--------|------|
| 인프라 (양쪽) | 100% | 통신 규약 + 런처 완성 |
| 기능 구현 (모드) | 67% | 12/18 완료, 6개 스텁 대기 |
| UI 편의 (앱) | 100% | 티어 편집/프리셋 import/export/잠금 완료 |
| 통계 도구 (앱) | 0% | profits.txt → xlsx 미착수 (포맷은 확정) |
| **프로젝트 전체** | **~72%** | 모드 스텁 구현이 유일한 큰 덩어리 |

---

## 📝 주의사항

### PZ B41 멀티플레이어 권한
- `IsoZombie`는 클라이언트 소유(owner `UdpConnection`) — 서버사이드 상태 변경은 소유 클라이언트 동기화 패킷에 덮어써짐
- 반드시 서버 → 브로드캐스트 → 각 클라이언트가 자신의 좀비만 킬

### PZ 스크립트 파일 포맷 (`media/scripts/*.txt`)
- `/* */` 블록 주석만 지원, `--`(Lua 스타일) 주석은 무효 — 파서가 바로 다음 아이템 블록 전체를 삼켜버림

### 한글 처리
- Lua 소스 내 직접 UTF-8 한글 리터럴 **사용 금지** → `\ddd` 바이트 이스케이프 또는 `getText()` 키 사용
- 번역 파일 (`IG_UI_*.txt`): UTF-16 BE + CRLF 필수

### modData 네임스페이싱
- 키 충돌 = 2틱마다 크로스모드 데이터 삭제 (조용히 발생 — Lua 전역 충돌보다 위험)
- 항상 모드 접두사 사용 (예: `hitmanBrain`, `hitmanZid`, `hitmanPreserve`)

### 기타
- `getGameVersion()`은 숫자가 아닌 Java 객체 반환 — 숫자 비교에 절대 사용 금지, B41 상수 하드코딩
- `DebugLog`는 콜러블 함수가 아닌 Java 클래스 객체 — `DebugLog(...)` 호출 시 `RuntimeException`
- Passive 스킬(근력/지구력) 만렙: `AddXP()`보다 `LevelPerk()` x10이 더 안정적

---

## 🎯 다음 단계

**즉시**: `random_skill_potion`의 `--` 주석 버그 수정 (`/* */`로 교체, `serum_strength` 스킵 문제) + `rise_up_dead_man` 인게임 테스트 (스피드 타입 유지 여부, 플레이어 시체 필터 여부 결정)
**단기**: 모드 스텁 1개 (revive_ticket, 가장 간단) 구현 → random_weapon
**중기**: vehicle_kit, secret_passage_kit, horde_night 완료
**후기**: CDDA + profits.txt → xlsx 스크립트
