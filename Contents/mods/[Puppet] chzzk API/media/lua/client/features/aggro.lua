local _a = {}

-- ── 소환 좀비 플레이어 어그로 (공용) v3: 엔진 어그로 인계(handoff) ──────────
-- 문제 근원 (IsoZombie.java 확증):
--   * 신규 스폰/부활 좀비는 TimeSinceSeenFlesh=100000, timeSinceRespondToSound
--     =1000000 으로 태어난다 — 랠리(ZombieGroupManager) 발동 조건
--     "둘 다 > 2000"(:2233)을 스폰 즉시 충족. 기본 행동이 산개다.
--   * v2(강제 spotted 펄스)는 어그로를 창 지속 중에만 인공 유지했다.
--     bForced=true는 지속성을 만드는 두 필드(TimeSinceSeenFlesh=0,
--     BonusSpotTime=120)를 정확히 건너뛰므로(:1631, :spotted tail) 창이
--     닫히면 아무것도 안 남아 랠리로 복귀 → 산발.
--
-- v3 원리 — 엔진의 자체 지속 어그로 루프에 태워보낸다:
--   spotted(target, false) 비강제 스팟이 확률 굴림에 성공하면
--     TimeSinceSeenFlesh=0  → target이 memory(기본 800유닛) 동안 유지,
--                             랠리 조건도 2000유닛 봉쇄
--     BonusSpotTime=120     → updateInternal:2137에서 엔진이 매 틱 스스로
--                             spotted(spottedLast,true) 재호출 (확률 1000000
--                             고정) — 이후 추격 유지는 전부 엔진 몫
--   즉 비강제 스팟 1회 성공 = 영구 인계. 창은 "유지 기간"이 아니라
--   "인계 부트스트랩 기간"이다.
--
-- 비강제 스팟 게이트와 대응:
--   * 거리 > 20타일 → 확률 -10000, 절대 실패 → 18타일 밖은 시도조차 안 하고
--     사운드(addSound)만. RespondToSound가 timeSinceRespondToSound=0으로
--     리셋(:1110)해 랠리를 봉쇄하면서 플레이어 쪽으로 끌어온다 → 18타일
--     안에 들어오면 시야 인계로 자연 전환.
--   * 등진 좀비(시선 내적<-0.4) → 확률 0 → 시도 전 faceThisObject로
--     돌려세움 (반대로 정면이면 x8~32 보너스, 10타일 내 추가 x11).
--   * 누운 좀비(onground/getup) → updateInternal이 target 블록을 스킵하는
--     상태라 인계 판정이 불가 → 일어날 때까지 시도 보류.
--
-- 인계 판정: 직전 펄스에서 spotted(false)가 성공했다면 250ms 뒤 스캔에서
--   z:getTarget() ~= nil 로 관측된다 (실패였다면 TimeSinceSeenFlesh>memory
--   체크가 1틱 내 target을 드랍). target 보유 = 인계 완료로 확정하고
--   그 좀비는 이후 완전히 손을 뗀다. 인계가 쌓일수록 펄스 비용이 0으로
--   수렴하므로 창을 길게 잡아도 부하가 없다.
--
-- 원격 좀비엔 spotted가 자체 no-op(소유 클라 권한)이므로 전 클라 브로드캐스트
-- + 각 클라 로컬 적용 구조 그대로. 서버/네트워크 부하 없음.

local SCAN_INTERVAL_MS = 250     -- 부트스트랩 펄스 간격
local LOG_INTERVAL_MS  = 2000    -- 창별 실적 로그 간격 (스팸 방지)
local SIGHT_RANGE      = 18      -- 비강제 스팟 시도 한계 (엔진 하드컷 20에 여유)
local SIGHT_RANGE2     = SIGHT_RANGE * SIGHT_RANGE
local _windows  = {}             -- {x, y, r, r2, expires, pid, lastLog, handoff, tried}
local _handoff  = {}             -- [onlineID] = true : 엔진 인계 완료 (전역)
local _lastScan = 0

local function pruneWindows()
    local now = getTimestampMs()
    for i = #_windows, 1, -1 do
        if now > _windows[i].expires then
            print("[PongDu][Aggro] window closed pid=" .. tostring(_windows[i].pid)
                .. " handoff=" .. tostring(_windows[i].handoff))
            table.remove(_windows, i)
        end
    end
    if #_windows == 0 then
        -- 전 창 종료 시 인계 기록 정리 (Kahlua엔 next 없음 — pairs로 비움)
        for k in pairs(_handoff) do _handoff[k] = nil end
    end
    return #_windows > 0
end

-- 좀비 1마리 인계 시도. 성공 여부가 아니라 "시도 여부"를 반환한다
-- (성공 판정은 다음 스캔에서 target 보유로 확인).
local function tryHandoff(z, target)
    return pcall(function()
        z:faceThisObject(target)
        z:spotted(target, false)
    end)
end

local function aggroScan()
    local cell = getCell()
    if not cell then return end
    local zlist = cell:getZombieList()
    if not zlist then return end
    local now = getTimestampMs()

    for wi = 1, #_windows do
        local w = _windows[wi]
        -- 대상 플레이어는 스캔 시점 좌표로 매번 재해석 (창 지속 중 이동 추적)
        local target = getPlayerByOnlineID(w.pid)
        if target and not target:isDead() then
            local tx = target:getX()
            local ty = target:getY()
            local tz = target:getZ()

            -- 원거리 유인 + 랠리 봉쇄: RespondToSound가
            -- timeSinceRespondToSound=0 리셋 → 랠리 2000유닛 봉쇄 (스캔당 1회)
            pcall(function()
                addSound(target, math.floor(tx), math.floor(ty), math.floor(tz),
                    w.r + 10, w.r + 10)
            end)

            local tried = 0
            for i = 0, zlist:size() - 1 do
                local z = zlist:get(i)
                if z and not z:isDead() then
                    local zid = z:getOnlineID()
                    if not _handoff[zid] then
                        local dx = z:getX() - w.x
                        local dy = z:getY() - w.y
                        if dx * dx + dy * dy <= w.r2 then
                            local remote = false
                            pcall(function() remote = z:isRemoteZombie() end)
                            if not remote then
                                local tgt
                                pcall(function() tgt = z:getTarget() end)
                                if tgt ~= nil then
                                    -- 직전 비강제 스팟(또는 자연 스팟)이 살아남음
                                    -- = TimeSinceSeenFlesh=0 확정 = 엔진 인계 완료
                                    _handoff[zid] = true
                                    w.handoff = w.handoff + 1
                                else
                                    local st
                                    pcall(function() st = z:getCurrentState() end)
                                    local lying = (st == ZombieOnGroundState.instance())
                                        or (st == ZombieGetUpState.instance())
                                    local ddx = z:getX() - tx
                                    local ddy = z:getY() - ty
                                    if not lying and ddx * ddx + ddy * ddy <= SIGHT_RANGE2 then
                                        if tryHandoff(z, target) then
                                            tried = tried + 1
                                        end
                                    end
                                    -- 18타일 밖/누움: addSound가 커버
                                end
                            end
                        end
                    end
                end
            end

            if now - w.lastLog >= LOG_INTERVAL_MS then
                w.lastLog = now
                print("[PongDu][Aggro] pulse tried=" .. tostring(tried)
                    .. " handoff=" .. tostring(w.handoff)
                    .. " pid=" .. tostring(w.pid))
            end
        elseif now - w.lastLog >= LOG_INTERVAL_MS then
            w.lastLog = now
            print("[PongDu][Aggro] target unresolved pid=" .. tostring(w.pid)
                .. (target and " (dead)" or " (not loaded)"))
        end
    end
end

Events.OnTick.Add(function()
    if not pruneWindows() then return end
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    local ok, err = pcall(aggroScan)
    if not ok then
        print("[PongDu][Aggro] scan error: " .. tostring(err))
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuAggro" or command ~= "Window" then return end
    local x   = tonumber(args and args["x"])
    local y   = tonumber(args and args["y"])
    local r   = tonumber(args and args["r"]) or 15
    local dur = tonumber(args and args["dur"]) or 8000
    local pid = tonumber(args and args["pid"])
    if not x or not y or not pid then return end
    local now = getTimestampMs()
    _windows[#_windows + 1] = {
        x = x, y = y, r = r, r2 = r * r,
        expires = now + dur, pid = pid,
        lastLog = 0, handoff = 0,
    }
    print("[PongDu][Aggro] window open @" .. tostring(x) .. "," .. tostring(y)
        .. " r=" .. tostring(r) .. " dur=" .. tostring(dur)
        .. " pid=" .. tostring(pid))
end)

return _a
