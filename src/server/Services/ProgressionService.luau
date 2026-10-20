--!strict
-- Server-authoritative account/weapon XP, unlock checks, loadout validation and anti-farm.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Leveling = require(Shared.Pure.Leveling)
local XPRules = require(Shared.Pure.XPRules)
local Weapons = require(Shared.Config.Weapons)
local Attachments = require(Shared.Config.Attachments)
local WeaponStats = require(Shared.Pure.WeaponStats)
local Progression = require(Shared.Config.Progression)
local Perks = require(Shared.Config.Perks)
local Killstreaks = require(Shared.Config.Killstreaks)
local Challenges = require(Shared.Config.Challenges)
local PerkRules = require(Shared.Pure.PerkRules)
local StreakRules = require(Shared.Pure.StreakRules)
local ChallengeRules = require(Shared.Pure.ChallengeRules)
local CosmeticRules = require(Shared.Pure.CosmeticRules)
local DataService = require(script.Parent.DataService)

type MatchLedger = {
	combatXP: number,
	objectiveXP: number,
	victimKills: { [number]: number },
	breakdown: { [string]: number },
	total: number,
}

local ProgressionService = {}

local ledgers: { [Player]: MatchLedger } = {}
local matchStartedAt = os.clock()
local lastLoadoutChange: { [Player]: number } = {}

local function ledger(player: Player): MatchLedger
	local l = ledgers[player]
	if not l then
		l = { combatXP = 0, objectiveXP = 0, victimKills = {}, breakdown = {}, total = 0 }
		ledgers[player] = l
	end
	return l
end

local function weaponEntry(profile: any, weaponId: string)
	local w = profile.weapons[weaponId]
	if not w then
		w = { level = 1, xp = 0, kills = 0 }
		profile.weapons[weaponId] = w
	end
	return w
end

function ProgressionService.isWeaponUnlocked(profile: any, weaponId: string): boolean
	local def = Weapons[weaponId]
	if not def then
		return false
	end
	return profile.account.level >= def.unlockLevel or profile.account.prestige > 0
end

function ProgressionService.weaponLevel(profile: any, weaponId: string): number
	local w = profile.weapons[weaponId]
	return if w then w.level else 1
end

-- Attachments still valid for the weapon at the player's current weapon level.
local function attachmentsFor(profile: any, weaponId: string, selection: any): { [string]: string }
	local def = Weapons[weaponId]
	if not def then
		return {}
	end
	return WeaponStats.sanitize(def, selection, ProgressionService.weaponLevel(profile, weaponId), Attachments)
end

-- Loadouts as the client should see them: copies, with stale attachments filtered out.
local function loadoutsView(profile: any): { Types.Loadout }
	local out = {}
	for i, l in profile.loadouts do
		out[i] = {
			name = l.name,
			primary = l.primary,
			secondary = l.secondary,
			primaryAttachments = attachmentsFor(profile, l.primary, l.primaryAttachments),
			secondaryAttachments = attachmentsFor(profile, l.secondary, l.secondaryAttachments),
			perks = PerkRules.sanitize(l.perks, profile.account.level, profile.account.prestige),
			streaks = StreakRules.sanitize(l.streaks, profile.account.level, profile.account.prestige),
		}
	end
	return out
end

-- Today's challenges as the client should see them. Rolls the set over on a new UTC day.
function ProgressionService.challengesView(player: Player, profile: any): { list: { Types.ChallengeView }, resetsAt: number }
	local now = os.time()
	if ChallengeRules.refresh(profile.challenges, player.UserId, now) then
		DataService.markDirty(player)
	end
	local list = {}
	for _, e in profile.challenges.daily do
		local def = Challenges.byId[e.id]
		if def then
			table.insert(list, { id = def.id, text = ChallengeRules.text(def), progress = e.progress, target = def.target, xp = def.xp, done = e.done })
		end
	end
	return { list = list, resetsAt = now + ChallengeRules.secondsLeft(now) }
end

-- The equipped cosmetics a player shows, with anything no longer owned dropped.
function ProgressionService.cosmeticsFor(player: Player): CosmeticRules.Equipped
	local profile = DataService.getProfile(player)
	if not profile then
		return CosmeticRules.sanitizeEquipped({ account = { prestige = 0 }, weapons = {}, stats = {}, inventory = {} }, nil)
	end
	return CosmeticRules.sanitizeEquipped(profile, profile.equipped)
end

-- Phase 5 hook for daily challenges and lifetime stats. Implemented by ChallengeService, which
-- replaces this function in its init(); callers (combat, modes, killstreaks) just report events.
function ProgressionService.recordEvent(_player: Player, _event: ChallengeRules.Event) end

function ProgressionService.summary(player: Player): Types.ProfileSummary?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local weapons = {}
	local unlocked = {}
	local weaponIds = {}
	for id in Weapons do
		local w = profile.weapons[id] or { level = 1, xp = 0, kills = 0, headshots = 0 }
		local p = Leveling.progress(w, Progression.WeaponCurve, Progression.MaxWeaponLevel)
		weapons[id] = { level = p.level, xp = p.xp, needed = p.needed, kills = w.kills, headshots = w.headshots or 0 }
		table.insert(weaponIds, id)
		if ProgressionService.isWeaponUnlocked(profile, id) then
			table.insert(unlocked, id)
		end
	end
	local level, prestige = profile.account.level, profile.account.prestige
	local unlockedPerks, unlockedStreaks = {}, {}
	for _, def in Perks.list do
		if PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			table.insert(unlockedPerks, def.id)
		end
	end
	for _, def in Killstreaks.list do
		if PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			table.insert(unlockedStreaks, def.id)
		end
	end
	local st = profile.stats
	local acct = Leveling.progress(profile.account, Progression.AccountCurve, Progression.MaxAccountLevel)
	return {
		userId = player.UserId,
		account = { level = acct.level, xp = acct.xp, needed = acct.needed, prestige = profile.account.prestige },
		weapons = weapons,
		stats = {
			kills = st.kills,
			deaths = st.deaths,
			matches = st.matches,
			wins = st.wins,
			headshots = st.headshots,
			assists = st.assists,
			captures = st.captures,
			plants = st.plants,
			defuses = st.defuses,
			tags = st.tags,
			dailies = st.dailies,
		},
		loadouts = loadoutsView(profile),
		selectedLoadout = profile.selectedLoadout,
		unlockedWeapons = unlocked,
		temporary = DataService.temporary,
		unlockedPerks = unlockedPerks,
		unlockedStreaks = unlockedStreaks,
		challenges = ProgressionService.challengesView(player, profile),
		cosmetics = {
			equipped = CosmeticRules.sanitizeEquipped(profile, profile.equipped),
			owned = CosmeticRules.owned(profile, weaponIds),
		},
		canPrestige = CosmeticRules.canPrestige(profile, Progression.MaxAccountLevel, Progression.MaxPrestige),
		maxPrestige = Progression.MaxPrestige,
	}
end

function ProgressionService.sync(player: Player)
	local s = ProgressionService.summary(player)
	if s then
		Net.event("ProfileSync"):FireClient(player, s)
	end
end

-- Core award path. `weaponId` optional. Returns the account XP actually granted.
local function grant(player: Player, accountAmount: number, reason: string, weaponId: string?, weaponAmount: number?): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	accountAmount = math.max(0, math.floor(accountAmount))
	local newAcct, gained = Leveling.add(profile.account, accountAmount, Progression.AccountCurve, Progression.MaxAccountLevel)
	profile.account.level, profile.account.xp = newAcct.level, newAcct.xp

	local weaponProgress, weaponGained = nil, 0
	if weaponId and weaponAmount and weaponAmount > 0 and Weapons[weaponId] then
		local w = weaponEntry(profile, weaponId)
		local nw, g = Leveling.add(w, weaponAmount, Progression.WeaponCurve, Progression.MaxWeaponLevel)
		w.level, w.xp = nw.level, nw.xp
		weaponGained = g
		weaponProgress = Leveling.progress(w, Progression.WeaponCurve, Progression.MaxWeaponLevel)
	end
	DataService.markDirty(player)

	local l = ledger(player)
	if accountAmount > 0 then
		l.breakdown[reason] = (l.breakdown[reason] or 0) + accountAmount
		l.total += accountAmount
	end

	local payload: Types.XPGainPayload = {
		amount = accountAmount,
		reason = reason,
		account = Leveling.progress(profile.account, Progression.AccountCurve, Progression.MaxAccountLevel),
		weaponId = weaponId,
		weapon = weaponProgress,
		leveledUp = gained > 0,
		weaponLeveledUp = weaponGained > 0,
	}
	Net.event("XPGain"):FireClient(player, payload)
	if gained > 0 then
		Net.event("Notify"):FireClient(player, ("LEVEL %d REACHED"):format(profile.account.level), "LevelUp")
	end
	if weaponGained > 0 and weaponId then
		Net.event("Notify"):FireClient(player, ("%s LEVEL %d"):format(Weapons[weaponId].displayName, weaponProgress and weaponProgress.level or 0), "LevelUp")
	end
	if gained > 0 or weaponGained > 0 then
		ProgressionService.sync(player)
	end
	return accountAmount
end

-- Combat awards pass through anti-farm decay and the per-minute ceiling.
function ProgressionService.onKill(killer: Player, victim: Player, weaponId: string?, headshot: boolean)
	local profile = DataService.getProfile(killer)
	if not profile then
		return
	end
	local l = ledger(killer)
	local count = (l.victimKills[victim.UserId] or 0) + 1
	l.victimKills[victim.UserId] = count
	local mult = XPRules.repeatMultiplier(Progression.RepeatVictimDecay, count)

	local acct = (Progression.AccountXP.Kill + (if headshot then Progression.AccountXP.Headshot else 0)) * mult
	acct = XPRules.capCombat(l.combatXP, acct, os.clock() - matchStartedAt, Progression.MaxCombatXPPerMinute)
	l.combatXP += acct
	local wxp = (Progression.WeaponXP.Kill + (if headshot then Progression.WeaponXP.Headshot else 0)) * mult

	profile.stats.kills += 1
	if headshot then
		profile.stats.headshots += 1
	end
	if weaponId and Weapons[weaponId] then
		weaponEntry(profile, weaponId).kills += 1
	end
	grant(killer, acct, if headshot then "Headshot Kill" else "Kill", weaponId, wxp)
end

function ProgressionService.onAssist(player: Player, weaponId: string?)
	local l = ledger(player)
	local acct = XPRules.capCombat(l.combatXP, Progression.AccountXP.Assist, os.clock() - matchStartedAt, Progression.MaxCombatXPPerMinute)
	l.combatXP += acct
	grant(player, acct, "Assist", weaponId, Progression.WeaponXP.Assist)
end

-- Objective awards (captures, hardpoint time, tags, plants, defuses, round wins). Capped per
-- minute like combat XP so a broken mode can never mint unbounded XP.
function ProgressionService.onObjective(player: Player, reason: string, amount: number)
	if amount <= 0 or not DataService.getProfile(player) then
		return
	end
	local l = ledger(player)
	local acct = XPRules.capCombat(l.objectiveXP, amount, os.clock() - matchStartedAt, Progression.MaxObjectiveXPPerMinute)
	l.objectiveXP += acct
	if acct > 0 then
		grant(player, acct, reason, nil, nil)
	end
end

function ProgressionService.onDeath(player: Player)
	local profile = DataService.getProfile(player)
	if profile then
		profile.stats.deaths += 1
		DataService.markDirty(player)
	end
end

function ProgressionService.beginMatch()
	table.clear(ledgers)
	matchStartedAt = os.clock()
end

-- Grants end-of-match XP and returns the player's breakdown for the results screen.
function ProgressionService.endMatch(player: Player, secondsPlayed: number, won: boolean, completed: boolean): { total: number, breakdown: { { reason: string, amount: number } } }?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	for _, entry in XPRules.matchCompletion(Progression.AccountXP, secondsPlayed, won, completed) do
		grant(player, entry.amount, entry.reason, nil, nil)
	end
	if completed then
		profile.stats.matches += 1
		if won then
			profile.stats.wins += 1
		end
	end
	local l = ledger(player)
	local breakdown = {}
	for reason, amount in l.breakdown do
		table.insert(breakdown, { reason = reason, amount = amount })
	end
	table.sort(breakdown, function(a, b)
		return a.amount > b.amount
	end)
	ProgressionService.sync(player) -- stats and XP changed; refresh the lobby view
	task.spawn(DataService.saveNow, player)
	return { total = l.total, breakdown = breakdown }
end

export type ResolvedLoadout = {
	primary: string,
	secondary: string,
	primaryAttachments: { [string]: string },
	secondaryAttachments: { [string]: string },
	perks: { string }, -- always three, one per tier, unlocked
	streaks: { string }, -- up to three, unlocked
}

-- The loadout a player spawns with. Locked weapons fall back to the defaults, and attachments
-- are re-validated against current weapon levels, so stored data can never grant anything unearned.
function ProgressionService.currentLoadout(player: Player): ResolvedLoadout
	local profile = DataService.getProfile(player)
	if not profile then
		return { primary = "VK7", secondary = "P12", primaryAttachments = {}, secondaryAttachments = {}, perks = table.clone(Perks.Defaults), streaks = table.clone(Killstreaks.Defaults) }
	end
	local l = profile.loadouts[profile.selectedLoadout] or profile.loadouts[1]
	local primaryOk = ProgressionService.isWeaponUnlocked(profile, l.primary)
	local secondaryOk = ProgressionService.isWeaponUnlocked(profile, l.secondary)
	return {
		primary = if primaryOk then l.primary else "VK7",
		secondary = if secondaryOk then l.secondary else "P12",
		primaryAttachments = if primaryOk then attachmentsFor(profile, l.primary, l.primaryAttachments) else {},
		secondaryAttachments = if secondaryOk then attachmentsFor(profile, l.secondary, l.secondaryAttachments) else {},
		perks = PerkRules.sanitize(l.perks, profile.account.level, profile.account.prestige),
		streaks = StreakRules.sanitize(l.streaks, profile.account.level, profile.account.prestige),
	}
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if lastLoadoutChange[player] and now - lastLoadoutChange[player] < 0.25 then
		return true
	end
	lastLoadoutChange[player] = now
	return false
end

function ProgressionService.init()
	Net.func("GetProfile").OnServerInvoke = function(player)
		DataService.waitForProfile(player, 15)
		return ProgressionService.summary(player)
	end

	Net.event("SelectLoadout").OnServerEvent:Connect(function(player, index)
		if rateLimited(player) or type(index) ~= "number" or index ~= index then
			return
		end
		local profile = DataService.getProfile(player)
		if not profile or index < 1 or index > #profile.loadouts or index % 1 ~= 0 then
			return
		end
		profile.selectedLoadout = index
		DataService.markDirty(player)
		ProgressionService.sync(player)
	end)

	Net.event("SetLoadout").OnServerEvent:Connect(function(player, index, loadout)
		if rateLimited(player) or type(index) ~= "number" or type(loadout) ~= "table" then
			return
		end
		local profile = DataService.getProfile(player)
		if not profile or index < 1 or index > #profile.loadouts or index % 1 ~= 0 then
			return
		end
		local primary, secondary = loadout.primary, loadout.secondary
		if type(primary) ~= "string" or type(secondary) ~= "string" then
			return
		end
		local pd, sd = Weapons[primary], Weapons[secondary]
		if not pd or pd.slot ~= "Primary" or not sd or sd.slot ~= "Secondary" then
			Net.event("Notify"):FireClient(player, "Invalid loadout", "Warning")
			return
		end
		if not ProgressionService.isWeaponUnlocked(profile, primary) or not ProgressionService.isWeaponUnlocked(profile, secondary) then
			Net.event("Notify"):FireClient(player, "That weapon is still locked", "Warning")
			return
		end
		local pa = if loadout.primaryAttachments == nil then {} else loadout.primaryAttachments
		local sa = if loadout.secondaryAttachments == nil then {} else loadout.secondaryAttachments
		local okP, whyP = WeaponStats.validate(pd, pa, ProgressionService.weaponLevel(profile, primary), Attachments)
		local okS, whyS = WeaponStats.validate(sd, sa, ProgressionService.weaponLevel(profile, secondary), Attachments)
		if not okP or not okS then
			local why = whyP or whyS
			Net.event("Notify"):FireClient(player, if why == "locked" then "That attachment is still locked" else "Invalid attachments", "Warning")
			ProgressionService.sync(player) -- let the client fall back to the stored loadout
			return
		end
		-- Phase 5: perks and streaks are optional in the request; nil keeps the stored selection
		local level, prestige = profile.account.level, profile.account.prestige
		if loadout.perks ~= nil then
			local ok, why = PerkRules.validate(loadout.perks, level, prestige)
			if not ok then
				Net.event("Notify"):FireClient(player, if why == "locked" then "That perk is still locked" else "Invalid perks", "Warning")
				ProgressionService.sync(player)
				return
			end
		end
		if loadout.streaks ~= nil then
			local ok, why = StreakRules.validate(loadout.streaks, level, prestige)
			if not ok then
				Net.event("Notify"):FireClient(player, if why == "locked" then "That killstreak is still locked" else "Invalid killstreaks", "Warning")
				ProgressionService.sync(player)
				return
			end
		end
		local entry = profile.loadouts[index]
		if loadout.perks ~= nil then
			entry.perks = PerkRules.sanitize(loadout.perks, level, prestige) -- validated: a fresh copy of strings
		end
		if loadout.streaks ~= nil then
			entry.streaks = StreakRules.sanitize(loadout.streaks, level, prestige)
		end
		entry.primary, entry.secondary = primary, secondary
		-- store fresh copies made of validated strings only
		entry.primaryAttachments = WeaponStats.sanitize(pd, pa, ProgressionService.weaponLevel(profile, primary), Attachments)
		entry.secondaryAttachments = WeaponStats.sanitize(sd, sa, ProgressionService.weaponLevel(profile, secondary), Attachments)
		DataService.markDirty(player)
		ProgressionService.sync(player)
	end)

	DataService.ProfileLoaded:Connect(function(player)
		ProgressionService.sync(player)
		if DataService.temporary then
			Net.event("Notify"):FireClient(player, "Progress saving is unavailable on this server; progress will not be kept.", "Warning")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ledgers[player] = nil
		lastLoadoutChange[player] = nil
	end)

	-- QA hook, Studio only and only on temporary (unsaved) profiles: set workspace attribute
	-- QA_GrantLevels to a number to put every player's account and weapons at that level.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("QA_GrantLevels"):Connect(function()
			local level = workspace:GetAttribute("QA_GrantLevels")
			if type(level) ~= "number" or not DataService.temporary then
				return
			end
			workspace:SetAttribute("QA_GrantLevels", nil)
			for _, player in Players:GetPlayers() do
				local profile = DataService.getProfile(player)
				if profile then
					profile.account.level = math.clamp(math.max(profile.account.level, level), 1, Progression.MaxAccountLevel)
					for id in Weapons do
						weaponEntry(profile, id).level = math.clamp(level, 1, Progression.MaxWeaponLevel)
					end
					ProgressionService.sync(player)
				end
			end
		end)
	end
end

function ProgressionService.start() end

return ProgressionService
