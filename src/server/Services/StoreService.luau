--!strict
-- Phase 6 store: credits and supply crates earned by play, cosmetic purchases with credits, crate
-- opening, and Robux bundles through an idempotent ProcessReceipt. Policy: Config/Store.luau.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Store = require(Shared.Config.Store)
local StoreRules = require(Shared.Pure.StoreRules)
local ChallengeRules = require(Shared.Pure.ChallengeRules)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local ACTION_INTERVAL = 0.5 -- seconds between buy / open requests per player

local StoreService = {}

local lastAction: { [Player]: number } = {}
local rng = Random.new()

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local last = lastAction[player]
	if last and now - last < ACTION_INTERVAL then
		return true
	end
	lastAction[player] = now
	return false
end

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

-- The real ProgressionService.reward: credits and crates for play.
local function reward(player: Player, kind: string, data: any)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local credits, crates, gearCrates = 0, 0, 0
	if kind == "levels" and type(data) == "number" and data > 0 then
		crates = StoreRules.addCrates(profile, "Supply", data * Store.CratePerLevelUp)
		local level = profile.account.level
		gearCrates = StoreRules.addCrates(profile, "Gear", StoreRules.gearCratesForLevels(level - data, level))
	elseif kind == "match" then
		credits = StoreRules.addCredits(profile, Store.Credits.MatchComplete + (if data == true then Store.Credits.MatchWin else 0))
	elseif kind == "challenge" then
		credits = StoreRules.addCredits(profile, Store.Credits.DailyChallenge)
		local today = ChallengeRules.day(os.time())
		if data == true and profile.dailyCrateDay ~= today then
			profile.dailyCrateDay = today
			crates = StoreRules.addCrates(profile, "Supply", Store.CrateForAllDailies)
		end
	end
	if credits > 0 then
		notify(player, ("+%d CREDITS"):format(credits), "Info")
	end
	if crates > 0 then
		notify(player, if crates == 1 then "+1 SUPPLY CRATE" else ("+%d SUPPLY CRATES"):format(crates), "Info")
	end
	if gearCrates > 0 then
		notify(player, if gearCrates == 1 then "+1 GEAR CRATE" else ("+%d GEAR CRATES"):format(gearCrates), "Info")
	end
	if credits > 0 or crates > 0 or gearCrates > 0 then
		DataService.markDirty(player)
		ProgressionService.sync(player)
	end
end

local function onBuy(player: Player, itemId: any)
	if rateLimited(player) or type(itemId) ~= "string" or #itemId > 32 then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local ok, why = StoreRules.buy(profile, itemId)
	if not ok then
		if why == "funds" then
			notify(player, "Not enough credits", "Warning")
		elseif why == "owned" then
			notify(player, "You already own that", "Warning")
		end
		return
	end
	DataService.markDirty(player)
	notify(player, ("Bought %s"):format(Store.shopById[itemId].name), "Info")
	ProgressionService.sync(player)
end

local function onOpen(player: Player, crateId: any)
	if rateLimited(player) or type(crateId) ~= "string" or #crateId > 32 then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local result, why = StoreRules.open(profile, crateId, rng:NextNumber())
	if not result then
		if why == "none" then
			notify(player, "No crates to open", "Warning")
		end
		return
	end
	DataService.markDirty(player)
	local payload: Types.CrateResultPayload = { crateId = crateId, kind = result.kind, id = result.id, credits = result.credits }
	Net.event("CrateOpened"):FireClient(player, payload)
	ProgressionService.sync(player)
end

-- Robux. Idempotent by PurchaseId: the grant and the receipt id are written to the profile in one
-- step, and the purchase is acknowledged only after that profile is saved. A retried receipt
-- (same PurchaseId) finds the id and is acknowledged without granting again.
local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they next join
	end
	local profile = DataService.waitForProfile(player, 15)
	if not profile or type(info.PurchaseId) ~= "string" or type(info.ProductId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = StoreRules.processReceipt(profile, info.PurchaseId, info.ProductId, os.time())
	if result == "unknown" then
		warn(("[StoreService] receipt for unknown product %d (purchase %s) left unprocessed"):format(info.ProductId, info.PurchaseId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	StoreRules.pruneReceipts(profile, os.time())
	DataService.markDirty(player)
	if not DataService.temporary and not DataService.saveNow(player) then
		-- not saved: do not acknowledge. The grant stays in this session and the id stays recorded,
		-- so the retry acknowledges without granting twice.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result == "granted" then
		local bundle = Store.premiumByProduct[info.ProductId]
		notify(player, ("%s added. Thank you!"):format(bundle.name), "LevelUp")
		ProgressionService.sync(player)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function loadPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- unknown policy counts as restricted. Nothing paid is random in this game either way; the
	-- flag is shown in the store and keeps any future paid random item off for these players.
	local restricted = not ok or (info :: any).ArePaidRandomItemsRestricted ~= false
	if player.Parent then
		player:SetAttribute("PaidRandomItemsRestricted", restricted)
		ProgressionService.sync(player)
	end
end

function StoreService.init()
	ProgressionService.reward = reward
	Net.event("BuyItem").OnServerEvent:Connect(onBuy)
	Net.event("OpenCrate").OnServerEvent:Connect(onOpen)
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(loadPolicy, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)

	-- QA hooks, Studio only and only on temporary (unsaved) profiles:
	--   QA_GrantCredits = N adds N credits; QA_GrantCrates = N adds N supply crates;
	--   QA_GrantGearCrates = N adds N gear crates.
	if RunService:IsStudio() then
		local function hook(name: string, apply: (any, number) -> ())
			workspace:GetAttributeChangedSignal(name):Connect(function()
				local n = workspace:GetAttribute(name)
				if type(n) ~= "number" or n ~= n or not DataService.temporary then
					return
				end
				workspace:SetAttribute(name, nil)
				for _, player in Players:GetPlayers() do
					local profile = DataService.getProfile(player)
					if profile then
						apply(profile, n)
						DataService.markDirty(player)
						ProgressionService.sync(player)
					end
				end
			end)
		end
		hook("QA_GrantCredits", function(profile, n)
			StoreRules.addCredits(profile, n)
		end)
		hook("QA_GrantCrates", function(profile, n)
			StoreRules.addCrates(profile, "Supply", n)
		end)
		hook("QA_GrantGearCrates", function(profile, n)
			StoreRules.addCrates(profile, "Gear", n)
		end)
	end
end

function StoreService.start() end

return StoreService
