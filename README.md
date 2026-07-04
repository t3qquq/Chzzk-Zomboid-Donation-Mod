# 라스트오더 (LastOrder) — 좀보이드 B41 치지직 후원연동 시스템

**최종 업데이트**: 2025-07-03

---

## 📋 프로젝트 구조

### 1. **퍼펫 API** (`gui.py`)
- **상태**: 핵심 기능 완료 ✅
- 역할: 치지직 후원 이벤트 → `rewards.txt` 릴레이
- 기술: PyQt5 + chzzkpy (비공식) + asyncio
- 배포: PyInstaller `--onefile` → `PuppetAPI.exe`

### 2. **인게임 모드** (`t3chzzkDonation`, "[Puppet] chzzk API")
- **상태**: 인프라 완료, 기능 8개 스텁 상태
- 역할: `rewards.txt` 읽기 → 게임 이펙트 트리거 (히트맨 NPC, 폭격, 텔레포트, 좀비 룰렛 등)
- 기술: B41 Lua + 멀티플레이어 통신 (`sendClientCommand`, modData)
- 아키텍처: featureId 기반 디스패치 (18개 슬롯, 8개만 구현)

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
- ✅ 라인 포맷 (모드 규약): `amount,featureId,sender,message` (URL 인코딩)
- ✅ 19세 방송 감지 + 쿠키 지원 (네이버 NID)
- ✅ 런처 게이트 (화이트리스트 검증 → 방송/PZ/인게임 상태 체크 → 자동 연동)
- ✅ 감시 (MainGuard): PZ 종료 감지 + 19세 전환 감지 + 인게임 이탈 감지

### 인게임 모드 (V2.0.0)
- ✅ 리워드 수신 인프라
  - `DonationReceiver.lua`: 4필드 파싱 (`amount,featureId,sender,message`)
  - `rewardManager.lua`: featureId 기반 디스패치 (18개 슬롯)
- ✅ 히트맨 NPC 시스템 (완전 독립)
  - 히트맨 AI (`HitmanBrain`, `Sharpshooter` + `Berserker` 전문성)
  - 플레이어/NPC 추적 (`GetTarget`)
  - modData 네임스페이싱 (충돌 방지)
- ✅ 폭격 시스템
  - 서버 브로드캐스트 패턴
  - 클라이언트별 소유 좀비만 킬 (권한 문제 해결)
- ✅ 기능 구현 완료 (10개)
  - debuff_roulette / buff_roulette / zombie_roulette
  - sprinter5 / bandit_melee / vaccine / bandit_ranged / exile / missile / backroom

---

## 🚧 진행 중 / 남은 작업

### **A. 모드: 8개 featureId 스텁 구현** (우선순위 높음)

#### `rewardManager.lua`에 등록된 스텁 8개

| featureId | 라벨 | 설계 메모 | 의존성 | 추정 난이도 |
|-----------|------|---------|--------|-----------|
| `random_weapon` | 랜덤 무기 뽑기 | 티어별 무기 등급 확률 테이블 (예: 1000원→T1 낮음, 100000원→T3 높음) | 인벤토리 API | ⭐⭐ |
| `random_skill_potion` | 랜덤 스킬 물약 | XP 부여 로직 (시크릿Z 참조) | Skill API | ⭐⭐ |
| `vehicle_kit` | 차량소환 키트 | `zone.a()` 안전지대 체크 재사용 + 차량 스폰 | 차량 API | ⭐⭐⭐ |
| `revive_ticket` | 즉시부활 티켓 | 기절 해제 (`immediate=true` 스텁만 등록) — 실제 구현 필요 | Status API | ⭐ |
| `cdda_spawn` | CDDA 스크리머/브루트 소환 | CDDA 모드 의존성 확인 후 | 외부 모드 | ⭐⭐⭐ |
| `secret_passage_kit` | 비밀통로 공사 키트 | `bombard.lua`의 `transmitAddObjectToSquare` 패턴 재사용 (벽 제거) | 맵 API | ⭐⭐⭐ |
| `horde_night` | 호드나이트 | 대량 좀비 스폰 + 서버 부하 관리 (스폰 큐 확장) | Spawn API | ⭐⭐⭐ |
| `rise_up_dead_man` | 시체 전부 부활 | 반경 제한 + 성능 최적화 (한꺼번에 10마리 제한?) | Corpse API | ⭐⭐⭐ |

**진행 전략**:
1. 난이도 ⭐부터 시작 (revive_ticket 제일 간단)
2. 각 구현 후 `luac5.1 -p` 문법 검증
3. B41 vanilla Lua 소스 참고:
   - `https://raw.githubusercontent.com/t3qquq/myPZ-Configs/refs/heads/main/pz41_lua_source.txt`
   - (bash_tool curl로 다운로드 후 grep으로 탐색, web_fetch 비권장 — 파일 크기)

---

### **B. 앱: `profits.txt` → xlsx 통계 스크립트** (우선순위 중간)

**배경**:
- `profits.txt` 형식: 한 줄당 `<streamer PZ 사용자명>\t<rewards.txt 한 줄>`
- 최근 3필드 → 4필드 변경: `amount,featureId,sender,message`
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

**예상 코드량**: ~200–300 lines (읽기 + 파싱 + 표 생성)

---

### **C. 기타 개선 (낮은 우선순위)**

#### 퍼펫 API
- 🔄 Naver 자동 로그인 (19+ 시 webview 팝업) — 비기술 사용자 UX 개선
- 🔄 코드 서명 (AV 경고 감소)

#### 모드
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
  3. 게임 이펙트 발동 (히트맨/폭격/텔레포트 등)

---

## 📊 진행 요약

| 영역 | 완료율 | 비고 |
|------|--------|------|
| 인프라 (양쪽) | 100% | 통신 규약 + 런처 완성 |
| 기능 구현 (모드) | 55% | 10/18 완료, 8개 스텁 대기 |
| UI 편의 (앱) | 100% | 티어 편집/프리셋 import/export 완료 |
| 통계 도구 (앱) | 0% | profits.txt → xlsx 미착수 |
| **프로젝트 전체** | **~65%** | 모드 스텁 구현이 유일한 큰 덩어리 |

---

## 📝 주의사항

### Lua 한글 처리
- 직접 UTF-8 한글 리터럴 **사용 금지** → `\ddd` 바이트 이스케이프 또는 `getText()` 키 사용
- 번역 파일 (`.txt`): UTF-16 BE + CRLF

### B41 멀티플레이어 권한
- 좀비 킬: 클라이언트 측에서만 서버 상태를 건드릴 수 있음
- 반드시 서버 → 브로드캐스트 → 각 클라이언트 에서 자신의 좀비만 킬

### modData 네임스페이싱
- 키 충돌 = 게임 크래시 또는 무한 상태 지우기 루프
- 항상 `modId_` 접두사 사용 (예: `hitmanBrain`, `hitmanZid`)

---

## 🎯 다음 단계

**즉시**: 모드 스텁 1개 (revive_ticket) 구현 → 테스트
**단기**: random_weapon, random_skill_potion 완료
**중기**: vehicle_kit, secret_passage_kit, horde_night 완료
**후기**: CDDA/rise_up_dead_man + profits.txt 스크립트
