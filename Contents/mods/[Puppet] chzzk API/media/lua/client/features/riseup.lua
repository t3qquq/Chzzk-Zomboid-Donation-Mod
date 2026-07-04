local _a = {}

-- 라이즈 업 데드 맨: 도네 플레이어 기준 반경 내 모든 시체(IsoDeadBody)를
-- 좀비로 되살린다 (반경은 폭격 missile 과 동일한 55).
--
-- 권한 구조는 폭격과 정반대다.
--   좀비(IsoZombie)  = 클라이언트 권한 -> 폭격 킬은 클라별 분산 처리 (bombard.lua)
--   시체(IsoDeadBody) = 서버 권한      -> 부활은 서버 핸들러 한 곳에서만 처리
-- 바닐라도 MP 시체 제거를 서버 커맨드(/removezombies)로 우회하고, 시체는
-- 청크 데이터 + reanimated.bin 으로 서버에 저장된다. 클라 브로드캐스트로
-- 각자 reanimateNow() 하면 클라 수만큼 좀비가 중복 생성될 수 있으므로 금지.
local RADIUS = 55

-- 도네 발동 진입점. 서버에 좌표/반경만 넘기고 실제 부활은 server.lua 의
-- DOServer["Schedule"]["RiseUp"] 이 수행한다.
function _a.a(player)
    if not player then return end
    getSoundManager():PlaySound("necromance", false, 1.0)
    sendClientCommand("Schedule", "PlayAlert", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = RADIUS,
    })
    sendClientCommand("Schedule", "RiseUp", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = RADIUS,
    })
end

return _a
