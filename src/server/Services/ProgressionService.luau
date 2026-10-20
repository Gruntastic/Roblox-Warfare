--!strict
-- Server-authoritative account/weapon XP, unlock checks, loadout validation and anti-farm.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Leveling = require(Shared.Pure.Leveling)
local XPRules = require(Shared.Pure.XPRules)
local Weapons = require(Shared.Config.Weapons)
local Progression = require(Shared.Config.Progression)
local DataService = require(script.Parent.DataService)

type MatchLedger = {
	combatXP: number,
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
		l = { combatXP = 0, victimKills = {}, breakdown = {}, total = 0 }
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

function ProgressionService.summary(player: Player): Types.ProfileSummary?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local weapons = {}
	local unlocked = {}
	for id in Weapons do
		local w = profile.weapons[id] or { level = 1, xp = 0, kills = 0 }
		local p = Leveling.progress(w, Progression.WeaponCurve, Progression.MaxWeaponLevel)
		weapons[id] = { level = p.level, xp = p.xp, needed = p.needed, kills = w.kills }
		if ProgressionService.isWeaponUnlocked(profile, id) then
			table.insert(unlocked, id)
		end
	end
	local acct = Leveling.progress(profile.account, Progression.AccountCurve, Progression.MaxAccountLevel)
	return {
		userId = player.UserId,
		account = { level = acct.level, xp = acct.xp, needed = acct.needed, prestige = profile.account.prestige },
		weapons = weapons,
		stats = { kills = profile.stats.kills, deaths = profile.stats.deaths, matches = profile.stats.matches, wins = profile.stats.wins },
		loadouts = table.clone(profile.loadouts),
		selectedLoadout = profile.selectedLoadout,
		unlockedWeapons = unlocked,
		temporary = DataService.temporary,
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

function ProgressionService.currentLoadout(player: Player): { primary: string, secondary: string }
	local profile = DataService.getProfile(player)
	if not profile then
		return { primary = "VK7", secondary = "P12" }
	end
	local l = profile.loadouts[profile.selectedLoadout] or profile.loadouts[1]
	local primary = if ProgressionService.isWeaponUnlocked(profile, l.primary) then l.primary else "VK7"
	local secondary = if ProgressionService.isWeaponUnlocked(profile, l.secondary) then l.secondary else "P12"
	return { primary = primary, secondary = secondary }
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
		local entry = profile.loadouts[index]
		entry.primary, entry.secondary = primary, secondary
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
end

function ProgressionService.start() end

return ProgressionService
