local _a = {}

local global = require("global")

-- ═══════════════════════════════════════════════════════════════════════════
--  화력 지원 (fire_support): 저격 / 드론 / 헬기 / 공수 중 1종 랜덤 발동. [스텁]
--
--  미사일 폭격(bombard)과 달리 "환경 무피해" 지원 계열. 지형/차량/시체 아이템을
--  건드리지 않고 반경 내 좀비만 처치한다. 시청자가 부담 없이 도움을 줄 수 있는
--  후원을 목표로 함.
--
--    저격 (sniper)     : 즉시 1회. 반경 넓음 / 킬 수 적음.
--    드론 (drone)      : 지속(짧음). 반경 좁음 / 짧은 간격.
--    헬기 (helicopter) : 지속(김). 반경 넓음 / 로터음 루프 + 기관총.
--    공수 (airborne)   : 히트맨 기반. 강하한 병력이 좀비를 사격.
--
--  ── 구현 시 지켜야 할 제약 (합의된 설계) ──────────────────────────────────
--  1. 좀비 킬은 반드시 해당 좀비의 소유 클라이언트에서 실행할 것.
--     서버에서 setHealth(0) 하면 소유 클라 sync 패킷에 덮여서 되살아난다.
--     -> 서버가 대상 산출 -> sendServerCommand 로 소유 클라에 킬 지시.
--  2. clearAttachedItems() 절대 호출 금지. 시체 아이템 증발 버그 원인 후보.
--  3. 사운드는 어그로와 분리한다. addSound() 를 부르지 않으면 좀비는 반응하지
--     않으므로, 헬기 로터음/총성을 크게 틀어도 어그로는 0으로 유지 가능.
--     (바닐라 헬기 이벤트가 좀비를 끌어모으는 건 이벤트 스크립트가 별도로
--      addSound 를 호출하기 때문 -- PZ-Library 확인 필요)
--  4. 루프 사운드는 재생 핸들을 보관했다가 종료 시 명시적으로 정지할 것.
--     중첩 후원 정책은 "지속시간 연장"(소리 1개 유지)으로 간다.
--  5. 대상 선정은 플레이어 기준 최근접 순. 랜덤으로 뽑으면 붙어있는 좀비가
--     안 죽어서 지원 체감이 사라진다. 반경 내 좀비 수 상한 필요.
--  6. 지속형은 duration 종료 시 반드시 타이머/이벤트를 해제할 것.
-- ═══════════════════════════════════════════════════════════════════════════

local KINDS = { "sniper", "drone", "helicopter", "airborne" }

-- 샌드박스 타입 필터: PongDu.FireSupport_<종류> 체크된 것만 룰렛 풀에 포함.
-- 옵션 없음(구 세이브) = 허용. 4종 전부 해제면 저격으로 폴백.
local KIND_OPTION = {
    sniper     = "FireSupport_Sniper",
    drone      = "FireSupport_Drone",
    helicopter = "FireSupport_Helicopter",
    airborne   = "FireSupport_Airborne",
}

local function pickKind()
    local sv = SandboxVars and SandboxVars.PongDu
    local pool = {}
    for _, k in ipairs(KINDS) do
        if not (sv and sv[KIND_OPTION[k]] == false) then
            pool[#pool + 1] = k
        end
    end
    if #pool == 0 then return "sniper" end
    return pool[ZombRand(#pool) + 1]
end

-- ── 종류별 실행부 (전부 미구현) ────────────────────────────────────────────
-- 각 함수는 player, sender 를 받아 해당 연출/처치를 수행한다.
-- 공통 파라미터는 샌드박스에서 읽되, SandboxVars 는 게임 로드 후에만 존재하므로
-- 반드시 발동 시점에 읽을 것.

local runners = {}

-- 저격: 즉시 1회. 반경 내 최근접 N마리 처치. 총성은 로컬 사운드만.
runners.sniper = function(player, sender)
    print("[PongDu] fire_support/sniper: not implemented yet")
    -- TODO: 서버에 대상 산출 요청 -> 소유 클라 킬 지시
end

-- 드론: 지속(짧음). interval 마다 소수 처치. 모터음 루프.
runners.drone = function(player, sender)
    print("[PongDu] fire_support/drone: not implemented yet")
    -- TODO: 지속형 틱 루프 + 루프 사운드 핸들 관리
end

-- 헬기: 지속(김). 로터음 루프 + 기관총. 어그로 없음.
runners.helicopter = function(player, sender)
    print("[PongDu] fire_support/helicopter: not implemented yet")
    -- TODO: 바닐라 헬기 사운드 이벤트명 확인 필요 (PZ-Library)
end

-- 공수: 히트맨 개체를 우호 진영으로 강하시켜 좀비를 사격.
runners.airborne = function(player, sender)
    print("[PongDu] fire_support/airborne: not implemented yet")
    -- TODO: 히트맨 타겟팅을 플레이어 -> 최근접 좀비로 교체,
    --       좀비의 히트맨 인식 여부 / MP 소유권 / duration 후 소멸 처리 확인
end

-- a(player, sender): 화력 지원 발동. 4종 중 1종을 뽑아 실행한다. [public name: .a]
function _a.a(player, sender)
    if not player then
        print("[PongDu] fire_support: aborted, player is nil")
        return
    end

    local kind = pickKind()
    print(string.format("[PongDu] fire_support START kind=%s sender=%s x=%d y=%d",
        tostring(kind), tostring(sender or ""),
        math.floor(player:getX()), math.floor(player:getY())))

    local run = runners[kind]
    if not run then
        print("[PongDu] fire_support: no runner for kind=" .. tostring(kind))
        return
    end

    run(player, sender or "")
    print("[PongDu] fire_support END kind=" .. tostring(kind))
end

-- b(): 진행 중인 화력 지원을 전부 정리한다 (루프 사운드 정지 + 타이머 해제).
-- 플레이어 사망/접속 종료 시 호출할 것. [public name: .b]
function _a.b()
    -- TODO: 지속형 구현 후 정리 로직 작성
end

return _a
