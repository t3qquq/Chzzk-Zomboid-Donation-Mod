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

-- 저격: 화면 밖 랜덤 지점에 저격수가 자리잡고, 특수좀비 우선으로 최대 N마리
-- 순차 사살. 대상 선정은 서버가 한다 -- 각 클라가 독립적으로 뽑으면 소유 좀비
-- 기준이라 총합이 N을 넘어버린다(폭격처럼 반경 전체 킬이 아니라 "N마리"가
-- 스펙이므로 서버 권위 선정이 필수).
runners.sniper = function(player, sender)
    local sv = SandboxVars and SandboxVars.PongDu
    local radius   = (sv and tonumber(sv.Sniper_Radius))   or 30
    local count    = (sv and tonumber(sv.Sniper_Count))    or 7
    local interval = (sv and tonumber(sv.Sniper_Interval)) or 700
    print(string.format("[PongDu] fire_support/sniper request r=%d n=%d interval=%d",
        radius, count, interval))
    sendClientCommand("PongDuFireSupport", "Sniper", {
        r = radius, n = count, iv = interval, sender = sender or "",
    })
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

-- ═══════════════════════════════════════════════════════════════════════════
--  예광탄 렌더러
--
--  HitmanProjectile.lua와 같은 원리(OnPreUIDraw + renderer:renderline)지만
--  두 가지가 다르다:
--   ① 히트맨은 스크린 좌표를 저장해두고 그 값을 직접 이동시킨다 -> 카메라가
--      움직이면 탄이 화면에 붙어서 같이 끌려다닌다. 여기선 월드(iso) 좌표만
--      저장하고 매 프레임 ToScreen으로 다시 변환한다.
--   ② 히트맨은 방향각으로 뻗기만 하고 목표에 수렴하지 않는다(순수 연출).
--      저격은 실제 명중이 있으므로 원점->목표를 보간해 정확히 꽂히게 한다.
--
--  가시성: 히트맨은 alpha 0.14 단선이라 밝은 지형에선 거의 안 보인다.
--  renderline에는 두께 인자가 없으므로 평행선 3개(심지 1 + 외곽 2)로
--  굵기를 만들고 alpha를 크게 올렸다.
-- ═══════════════════════════════════════════════════════════════════════════

local TRACER_TEX  = getTexture("media/textures/mask_white.png")
local TRACER_STEP = 0.16      -- 프레임당 진행률 (1/0.16 = 약 7프레임에 도달)
local TRACER_SEG  = 0.20      -- 그려지는 선분 길이 (진행률 단위)
local ORIGIN_ALT  = 95        -- 원점 고도(px). PZ엔 3D가 없어 스크린 Y로 위조한다
local TARGET_ALT  = 70        -- 목표 고도(px). 좀비 상반신 높이

local _tracers = {}

local function addTracer(ox, oy, oz, tx, ty, tz)
    _tracers[#_tracers + 1] = {
        ox = ox, oy = oy, oz = oz,
        tx = tx, ty = ty, tz = tz,
        t = 0, hit = 0,
    }
end

local function drawTracers()
    if #_tracers == 0 then return end
    if isServer() then return end
    if not isIngameState() then return end

    local zoom = getCore():getZoom(0)
    if not zoom or zoom == 0 then return end
    local renderer = getRenderer()

    for i = #_tracers, 1, -1 do
        local tr = _tracers[i]
        local sx, sy = ISCoordConversion.ToScreen(tr.ox, tr.oy, tr.oz)
        local ex, ey = ISCoordConversion.ToScreen(tr.tx, tr.ty, tr.tz)
        sx = sx / zoom
        sy = sy / zoom - ORIGIN_ALT / zoom
        ex = ex / zoom
        ey = ey / zoom - TARGET_ALT / zoom

        if tr.t < 1 then
            local a1 = tr.t
            local a2 = math.min(tr.t + TRACER_SEG, 1)
            local x1 = math.floor(sx + (ex - sx) * a1)
            local y1 = math.floor(sy + (ey - sy) * a1)
            local x2 = math.floor(sx + (ex - sx) * a2)
            local y2 = math.floor(sy + (ey - sy) * a2)
            -- 외곽(어둡고 넓게) -> 심지(밝게) 순으로 3줄
            renderer:renderline(TRACER_TEX, x1, y1 - 1, x2, y2 - 1, 1, 0.86, 0.45, 0.35)
            renderer:renderline(TRACER_TEX, x1, y1 + 1, x2, y2 + 1, 1, 0.86, 0.45, 0.35)
            renderer:renderline(TRACER_TEX, x1, y1,     x2, y2,     1, 1,    0.90, 0.90)
            -- 총구 화염: 처음 두 프레임만 원점에 짧고 밝게
            if tr.t < TRACER_STEP * 2 then
                local fx = math.floor(sx + (ex - sx) * 0.03)
                local fy = math.floor(sy + (ey - sy) * 0.03)
                renderer:renderline(TRACER_TEX, math.floor(sx), math.floor(sy), fx, fy,
                    1, 0.92, 0.55, 0.95)
            end
            tr.t = tr.t + TRACER_STEP
        else
            -- 탄착 섬광: 목표 지점에 십자로 몇 프레임
            tr.hit = tr.hit + 1
            local alpha = 0.85 - tr.hit * 0.17
            if alpha > 0 then
                local sz = math.floor(7 / zoom)
                local cxp, cyp = math.floor(ex), math.floor(ey)
                renderer:renderline(TRACER_TEX, cxp - sz, cyp, cxp + sz, cyp, 1, 0.80, 0.40, alpha)
                renderer:renderline(TRACER_TEX, cxp, cyp - sz, cxp, cyp + sz, 1, 0.80, 0.40, alpha)
            end
            if tr.hit > 5 then table.remove(_tracers, i) end
        end
    end
end

Events.OnPreUIDraw.Add(drawTracers)

-- ═══════════════════════════════════════════════════════════════════════════
--  사격 큐 (저격 공용)
-- ═══════════════════════════════════════════════════════════════════════════

local _shots = {}

local function findZombieById(id)
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return nil end
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and z:getOnlineID() == id then return z end
    end
    return nil
end

-- 즉사 처리. B41 MP에서 좀비는 클라 권한이므로 소유 클라에서만 호출해야 한다
-- (서버 setHealth는 소유 클라 동기화 패킷에 덮인다).
-- bombard.killZombiesAround와 같은 시퀀스지만 clearAttachedItems()는 부르지
-- 않는다 -- 지원 계열은 시체 아이템 손실이 없어야 하고, 이 호출이 시체 아이템
-- 증발 버그의 원인 후보다.
local function killZombieNow(z)
    local cell = getCell()
    if not cell then return end
    z:setCrawler(true)
    z:setHealth(0)
    z:changeState(ZombieOnGroundState.instance())
    z:setAttackedBy(cell:getFakeZombieForHit())
    z:becomeCorpse()
end

local function processShots()
    if #_shots == 0 then return end
    local now = getTimestampMs()
    for i = #_shots, 1, -1 do
        local sh = _shots[i]
        if now >= sh.at then
            table.remove(_shots, i)
            local z = findZombieById(sh.id)
            -- 서버가 보낸 좌표는 선정 시점 값이라 좀비가 움직였을 수 있다.
            -- 살아있으면 현재 좌표로 조준한다.
            local tx, ty, tz = sh.x, sh.y, sh.z
            if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end
            addTracer(sh.ox, sh.oy, sh.oz, tx, ty, tz)

            -- 총성: 비위치성 로컬 재생. addSound()를 부르지 않으므로 어그로 0.
            local okS = pcall(function()
                getSoundManager():PlaySound("MSR788Shoot", false, 1.0)
            end)
            if not okS then print("[PongDu] fire_support/sniper: shot sound failed") end

            if z and not z:isDead() then
                if z:isRemoteZombie() then
                    -- 소유 클라가 아님 -> 연출만. 킬은 소유 클라가 수행한다.
                    pcall(function() z:playSound("BulletHitBody") end)
                else
                    local ok, err = pcall(function() killZombieNow(z) end)
                    if ok then
                        pcall(function() z:playSound("BulletHitBody") end)
                        print("[PongDu] fire_support/sniper KILL zid=" .. tostring(sh.id))
                    else
                        print("[PongDu] fire_support/sniper KILL FAILED zid="
                            .. tostring(sh.id) .. " err=" .. tostring(err))
                    end
                end
            else
                print("[PongDu] fire_support/sniper: target gone zid=" .. tostring(sh.id))
            end
        end
    end
end

Events.OnTick.Add(processShots)

-- 서버가 산출한 사격 명령 수신. 전 클라에 브로드캐스트되며, 각 클라는
-- 연출을 전부 그리되 킬은 자기가 소유한 좀비에 대해서만 수행한다.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuFireSupport" then return end
    if command ~= "SniperFire" then return end
    if not args or not args.shots then return end

    local iv  = tonumber(args.iv) or 700
    local ox  = tonumber(args.ox) or 0
    local oy  = tonumber(args.oy) or 0
    local oz  = tonumber(args.oz) or 0
    local now = getTimestampMs()
    local n   = 0

    for idx, sh in ipairs(args.shots) do
        local id = tonumber(sh.id)
        if id then
            n = n + 1
            _shots[#_shots + 1] = {
                at = now + (idx - 1) * iv,
                id = id,
                x  = tonumber(sh.x) or 0,
                y  = tonumber(sh.y) or 0,
                z  = tonumber(sh.z) or 0,
                ox = ox, oy = oy, oz = oz,
            }
        end
    end
    print(string.format("[PongDu] fire_support/sniper SniperFire received shots=%d interval=%d origin=%d,%d",
        n, iv, math.floor(ox), math.floor(oy)))
end)

-- b(): 진행 중인 화력 지원을 전부 정리한다 (예광탄 + 대기 중인 사격).
-- 플레이어 사망/접속 종료 시 호출할 것. [public name: .b]
function _a.b()
    _tracers = {}
    _shots   = {}
end

return _a
