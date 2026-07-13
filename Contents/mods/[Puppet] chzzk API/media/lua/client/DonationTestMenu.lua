--
-- ***********************************
-- *** 도네이션 테스트 어드민 메뉴  ***
-- ***********************************
-- MutantMenu.lua의 WorldContextMenuPre 패턴 이식. 어드민(또는 디버그)일 때만
-- 우클릭 컨텍스트메뉴에 "donation test" 항목이 뜨고, 서브메뉴에 등록된
-- featureId 전체가 알파벳순으로 나열된다 (rewardManager.getFeatureIds).
--
-- 항목 클릭 = PongDuDonationTest.inject() 호출 -> 실제 도네이션과 완전히 같은
-- 경로(donationQueue -> 큐박스 슬롯 -> 안전지대 락 -> 카운트다운 -> 발동)를
-- 태운다. MutantMenu의 특좀 소환처럼 즉시 발동이 아니라 "가짜 후원 1건"이
-- 들어온 것과 동일하게 동작하는 게 목적. 통계(PongDuStats)에는 안 잡힘.
--

DonationTestMenu = DonationTestMenu or {}

local rewardManager = require("rewards/rewardManager")

function DonationTestMenu.Fire(player, featureId)
    if PongDuDonationTest and PongDuDonationTest.inject then
        PongDuDonationTest.inject(featureId, "Admin", "0", "")
    end
end

function DonationTestMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    if not (isAdmin() or isDebugEnabled()) then return end

    local player = getSpecificPlayer(playerID)
    if not player then return end

    local testOption = context:addOption("donation test")
    local testMenu = context:getNew(context)
    context:addSubMenu(testOption, testMenu)

    for _, featureId in ipairs(rewardManager.getFeatureIds()) do
        testMenu:addOption(featureId, player, DonationTestMenu.Fire, featureId)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(DonationTestMenu.WorldContextMenuPre)
