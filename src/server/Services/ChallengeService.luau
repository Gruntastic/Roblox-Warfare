--!strict
-- Daily challenges, lifetime stats for titles, prestige and cosmetic equips (Phase 5).
-- Contract: docs/PHASE5_CONTRACT.md. Gameplay code reports events through
-- ProgressionService.recordEvent; init() replaces that stub with `recordEvent` below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Progression = require(Shared.Config.Progression)
local Challenges = require(Shared.Config.Challenges)
local Cosmetics = require(Shared.Config.Cosmetics)
local ChallengeRules = require(Shared.Pure.ChallengeRules)
local CosmeticRules = require(Shared.Pure.CosmeticRules)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local MatchService = require(script.Parent.MatchService)
local ChallengeEvents = require(script.Parent.ChallengeEvents)

local PRESTIGE_INTERVAL = 2 -- seconds between prestige requests
local EQUIP_INTERVAL = 0.25 -- 4 equips per second

local ChallengeService = {}

local lastPrestige: { [Player]: number } = {}
local lastEquip: { [Player]: number } = {}

local function rateLimited(map: { [Player]: number }, player: Player, interval: number): boolean
	local now = os.clock()
	local last = map[player]
	if last and now - last < interval then
		return true
	end
	map[player] = now
	return false
end

local function progressSum(state: ChallengeRules.State): number
	local sum = 0
	for _, e in state.daily do
		sum += e.progress
	end
	return sum
end

-- The real ProgressionService.recordEvent: today's challenges, lifetime stats, rewards.
local function recordEvent(player: Player, event: ChallengeRules.Event)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local changed = ChallengeRules.refresh(profile.challenges, player.UserId, os.time())
	if ChallengeEvents.applyStats(profile.stats :: any, event) then
		changed = true
	end
	local before = progressSum(profile.challenges)
	local completed = ChallengeRules.record(profile.challenges, event)
	if progressSum(profile.challenges) ~= before then
		changed = true
	end
	for _, def in completed do
		-- fixed reward, outside the per-minute caps (those guard combat and objective farming)
		ProgressionService.grantBonus(player, def.xp, "Daily Challenge")
		profile.stats.dailies += 1
		Net.event("Notify"):FireClient(player, ("Challenge complete: %s  +%d XP"):format(ChallengeRules.text(def), def.xp), "Challenge")
	end
	if changed then
		DataService.markDirty(player)
		ProgressionService.sync(player)
	end
end

local function onPrestige(player: Player, confirm: any)
	if rateLimited(lastPrestige, player, PRESTIGE_INTERVAL) or type(confirm) ~= "string" or confirm ~= "PRESTIGE" then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if MatchService.canFight(player) then
		Net.event("Notify"):FireClient(player, "Prestige is only available outside a match", "Warning")
		return
	end
	if not CosmeticRules.canPrestige(profile, Progression.MaxAccountLevel, Progression.MaxPrestige) then
		Net.event("Notify"):FireClient(player, "Prestige is not available yet", "Warning")
		return
	end
	-- Account level and XP reset; weapon levels (and so attachment unlocks), stats and cosmetics
	-- are untouched, and prestige > 0 keeps every weapon, perk and killstreak unlocked.
	CosmeticRules.applyPrestige(profile)
	DataService.markDirty(player)
	task.spawn(DataService.saveNow, player) -- yields on the DataStore; the reply should not wait
	Net.event("Notify"):FireClient(player, ("Prestige %d reached"):format(profile.account.prestige), "LevelUp")
	ProgressionService.sync(player)
end

local function onEquipCosmetic(player: Player, kind: any, id: any, weaponId: any)
	if rateLimited(lastEquip, player, EQUIP_INTERVAL) then
		return
	end
	if type(kind) ~= "string" or type(id) ~= "string" or (weaponId ~= nil and type(weaponId) ~= "string") then
		return
	end
	-- camos are stored per weapon id, so only real weapon ids are accepted as keys
	if kind == "Camo" and not (type(weaponId) == "string" and Weapons[weaponId]) then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local ok, why = CosmeticRules.canEquip(profile, kind, id, weaponId)
	if not ok then
		if why == "locked" then
			Net.event("Notify"):FireClient(player, "That cosmetic is still locked", "Warning")
		end
		return
	end
	local equipped = profile.equipped
	if kind == "Camo" then
		if id == Cosmetics.DefaultCamo then
			equipped.camos[weaponId] = nil :: any -- Factory is the default: no entry
		else
			equipped.camos[weaponId] = id
		end
	elseif kind == "Title" then
		equipped.title = id
	elseif kind == "Emblem" then
		equipped.emblem = if id == "" then nil else id
	end
	DataService.markDirty(player)
	ProgressionService.sync(player)
end

function ChallengeService.init()
	ProgressionService.recordEvent = recordEvent

	Net.event("Prestige").OnServerEvent:Connect(onPrestige)
	Net.event("EquipCosmetic").OnServerEvent:Connect(onEquipCosmetic)

	Players.PlayerRemoving:Connect(function(player)
		lastPrestige[player] = nil
		lastEquip[player] = nil
	end)

	-- QA hooks, Studio only and only on temporary (unsaved) profiles:
	--   QA_GrantStats = N: every lifetime stat and every weapon's kills to at least N (headshots
	--     to at least N/3), so titles and camos can be checked.
	--   QA_CompleteChallenges = true: completes today's challenges through the normal path, so
	--     the XP grant and the notifications fire.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("QA_GrantStats"):Connect(function()
			local n = workspace:GetAttribute("QA_GrantStats")
			if type(n) ~= "number" or n ~= n or not DataService.temporary then
				return
			end
			workspace:SetAttribute("QA_GrantStats", nil)
			local weaponIds = {}
			for id in Weapons do
				table.insert(weaponIds, id)
			end
			for _, player in Players:GetPlayers() do
				local profile = DataService.getProfile(player)
				if profile then
					ChallengeEvents.raiseStats(profile, math.min(n, 1e6), weaponIds)
					DataService.markDirty(player)
					ProgressionService.sync(player)
				end
			end
		end)
		workspace:GetAttributeChangedSignal("QA_CompleteChallenges"):Connect(function()
			if workspace:GetAttribute("QA_CompleteChallenges") ~= true or not DataService.temporary then
				return
			end
			workspace:SetAttribute("QA_CompleteChallenges", nil)
			for _, player in Players:GetPlayers() do
				local profile = DataService.getProfile(player)
				if profile then
					ChallengeRules.refresh(profile.challenges, player.UserId, os.time())
					for _, e in profile.challenges.daily do
						local def = Challenges.byId[e.id]
						if def and not e.done then
							recordEvent(player, ChallengeEvents.completionEvent(def, e.progress))
						end
					end
				end
			end
		end)
	end
end

function ChallengeService.start() end

return ChallengeService
