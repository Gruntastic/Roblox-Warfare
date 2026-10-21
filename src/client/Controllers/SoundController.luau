--!strict
-- Plays the Config/Audio sound slots. Gameplay code raises ClientState.Sfx(slot, position?, pitch?)
-- and this module also listens for hit confirms, damage, ADS and other players' shots. A slot whose
-- id is 0 is skipped, so the game stays silent until sounds are uploaded. 2D sounds play from
-- SoundService; positioned ones from a temporary attachment so they fall off with distance.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Audio = require(Shared.Config.Audio)

local SoundController = {}

local MAX_PER_SLOT_PER_SECOND = 20 -- guards against a flood (e.g. many shotguns at once)
local rng = Random.new()
local recent: { [string]: { t: number, n: number } } = {}
local templates: { [string]: Sound } = {}

local function template(name: string, slot: Audio.Slot): Sound
	local existing = templates[name]
	if existing then
		return existing
	end
	local t = Instance.new("Sound")
	t.Name = name
	t.SoundId = "rbxassetid://" .. tostring(slot.id)
	t.Volume = slot.volume or 0.6
	templates[name] = t
	return t
end

function SoundController.play(name: string, position: Vector3?, pitch: number?)
	local slot = Audio[name]
	if name == "Shot.Distant" and (not slot or slot.id == 0) then
		name, slot = "Shot.AssaultRifle", Audio["Shot.AssaultRifle"]
	end
	if not slot or slot.id == 0 then
		return
	end
	local now = os.clock()
	local r = recent[name]
	if r == nil or now - r.t > 1 then
		r = { t = now, n = 0 }
		recent[name] = r
	end
	assert(r)
	r.n += 1
	if r.n > MAX_PER_SLOT_PER_SECOND then
		return
	end
	local sound = template(name, slot):Clone()
	local jitter = slot.pitchJitter or 0
	sound.PlaybackSpeed = 1 + (slot.pitch or 0) + (pitch or 0) + (if jitter > 0 then rng:NextNumber(-jitter, jitter) else 0)
	if position then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = workspace.Terrain
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = if string.sub(name, 1, 7) == "Streak." then 1000 else 400
		sound.Parent = holder
		sound.Ended:Once(function()
			holder:Destroy()
		end)
		task.delay(10, function()
			if holder.Parent then
				holder:Destroy()
			end
		end)
		sound:Play()
	else
		SoundService:PlayLocalSound(sound)
	end
end

function SoundController.init()
	ClientState.Sfx:Connect(SoundController.play)
	ClientState.HitConfirm:Connect(function(p)
		SoundController.play(if p.headshot then "HitHeadshot" else "HitMarker")
		if p.killed then
			task.delay(0.08, SoundController.play, "KillConfirm")
		end
	end)
	ClientState.DamageTaken:Connect(function()
		SoundController.play("HurtPlayer")
	end)
	ClientState.AdsChanged:Connect(function(on: boolean)
		if on then
			SoundController.play("AdsIn")
		end
	end)
	ClientState.StreakEvent:Connect(function(kind: string, data: { [string]: any })
		if kind == "Incoming" and type(data.positions) == "table" then
			-- one warning whistle at the first landing point (heard by everyone nearby)
			local first = data.positions[1]
			SoundController.play("Streak.MortarIncoming", if typeof(first) == "Vector3" then first else nil)
		elseif kind == "Impact" and typeof(data.position) == "Vector3" then
			SoundController.play("Streak.Explosion", data.position)
		end
	end)
	Net.event("Tracer").OnClientEvent:Connect(function(_shooterId: number, origin: Vector3)
		SoundController.play("Shot.Distant", origin)
	end)
end

return SoundController
