-- ═══════════════════════════════════════════════════════════════════════════
--  ReanimatedPlayer '알몸 부활' 보정 패치 (클라 전용)
--
--  ── 원인 (B41 41.78.19 바닐라 소스 확정) ──────────────────────────────────
--  IsoDeadBody.reanimate()는 isFakeDead()==false인 모든 시체(RiseUp 대량부활,
--  플레이어 좀비화 사망 포함)를 setReanimatedPlayer(true)로 마킹하고 외형을
--  SharedDescriptors.createPlayerZombieDescriptor로 별도 등록한다. 이 외형은
--  좀비 sync와 별개인 ZombieDescriptors 패킷으로 클라에 push되는데
--  (GameClient.receiveZombieDescriptors), 클라가 좀비를 먼저 그리면
--  IsoZombie.dressInPersistentOutfitID → PersistentOutfits →
--  SharedDescriptors.ApplyReanimatedPlayerOutfit이 로컬
--  PlayerZombieDescriptors[슬롯]에서 null을 만나 '조용히 아무것도 안 하고'
--  비주얼만 clear된 채 알몸으로 굳는다. 협동서버는 호스트여도 서버가 별도
--  프로세스라 호스트 클라도 같은 패킷 경로를 타므로 호스트 화면에서도 발생.
--
--  ── 보정 방식 ─────────────────────────────────────────────────────────────
--  클라 상시 스윕: isReanimatedPlayer()==true && worn==0 && pid~=0 인 좀비에
--  z:dressInPersistentOutfitID(z:getPersistentOutfitID()) 를 재호출한다.
--  디스크립터가 도착해 있으면 useDescriptor()가 외형+착의를 복사해 즉시
--  복구되고, 아직이면 아무 일도 안 하므로(멱등) 다음 스윕에서 재시도한다.
--  디스크립터는 push로 늦게라도 반드시 도착하므로 결국 복구된다.
--
--  트리거에 묶지 않는 이유: RiseUp뿐 아니라 좀비화 사망도 같은 원인이라
--  특정 커맨드(MutantReviveDebug 등) 기반 스윕은 케이스를 놓친다.
--
--  서버/네트워크 영향 없음 — 순수 클라 로컬 재착의라 sync 부작용 없음.
--  riseupDiag.lua와 동시 적용 가능(진단이 DETECT→RESOLVED로 효과를 계측).
--
--  로그 태그: [PongDu][Redress]
-- ═══════════════════════════════════════════════════════════════════════════

local SCAN_INTERVAL_MS = 250        -- 스윕 주기
local RETRY_GIVEUP_MS  = 60000      -- 좀비당 최대 재시도 시간(그 이후 포기)
local _lastScan = 0
local _retry = {}                   -- [onlineID] = { firstMs, tries }

local function wornCount(z)
    local n = -1
    pcall(function() n = z:getWornItems():size() end)
    return n
end

local function scan()
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if not player then return end
        local cell = player:getCell()
        if not cell then return end

        local now = getTimestampMs()
        local zlist = cell:getZombieList()
        local seen = {}

        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if z and z:isReanimatedPlayer() then
                local zid = z:getOnlineID()
                seen[zid] = true
                local worn = wornCount(z)
                local rec = _retry[zid]

                if worn == 0 then
                    local pid = z:getPersistentOutfitID()
                    if pid and pid ~= 0 then
                        if not rec then
                            rec = { firstMs = now, tries = 0 }
                            _retry[zid] = rec
                        end
                        if (now - rec.firstMs) <= RETRY_GIVEUP_MS then
                            rec.tries = rec.tries + 1
                            -- 디스크립터 도착 시에만 실제 복구됨. 미도착이면 no-op.
                            pcall(function()
                                z:dressInPersistentOutfitID(pid)
                            end)
                            if wornCount(z) > 0 then
                                pcall(function() z:resetModelNextFrame() end)
                                print(string.format(
                                    "[PongDu][Redress] fixed zid=%s tries=%d after=%dms",
                                    tostring(zid), rec.tries, now - rec.firstMs
                                ))
                                _retry[zid] = nil
                            end
                        end
                    end
                    -- pid==0이면 좀비 sync 자체가 아직이므로 다음 스윕에서 재확인
                elseif rec then
                    -- 스윕 외 경로(늦은 push 직후 자체 재드레스 등)로 복구된 경우
                    _retry[zid] = nil
                end
            end
        end

        -- 셀에서 사라진 좀비 정리
        for zid in pairs(_retry) do
            if not seen[zid] then _retry[zid] = nil end
        end
    end)
    if not ok then
        print("[PongDu][Redress] scan error: " .. tostring(err))
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    scan()
end)

print("[PongDu][Redress] loaded (ReanimatedPlayer 알몸 부활 보정, 클라 전용)")
