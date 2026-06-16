local ReplicatedStorage         = game:GetService("ReplicatedStorage")
local setupProximityPromptShown = require(ReplicatedStorage.RosaRbxPipeline.ingestion["default-metrics"]["proximity-prompt-shown"])

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

local function makeHandler()
	local calls = {}
	return {
		calls = calls,
		addClientEvent = function(_, event)
			table.insert(calls, event)
		end,
	}
end

local function makeLocalPlayer(rootPos)
	local root = rootPos and { Position = rootPos } or nil
	return {
		Character = {
			FindFirstChild = function(_, name)
				if name == "HumanoidRootPart" then return root end
			end,
		},
	}
end

local function makePrompt(objectText, actionText, partPos)
	local part = partPos and {
		Position = partPos,
		IsA      = function(_, class) return class == "BasePart" end,
	} or nil
	return {
		ObjectText = objectText or "",
		ActionText = actionText or "Use",
		Parent     = part,
	}
end

local function makeServices(promptShown, localPlayer, getTime)
	return {
		ProximityPromptService = { PromptShown = promptShown },
		Players                = { LocalPlayer = localPlayer },
		getTime                = getTime,
	}
end

return function()
	describe("ProximityPromptShown", function()

		it("fires ProximityPromptShown when a prompt is shown", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("Chest", "Open", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("ProximityPromptShown")
		end)

		it("uses ObjectText as promptName when non-empty", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("Treasure Chest", "Open", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].custom.promptName).to.equal("Treasure Chest")
		end)

		it("falls back to ActionText when ObjectText is empty", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("", "Interact", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].custom.promptName).to.equal("Interact")
		end)

		it("calculates distanceToPrompt correctly", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(Vector3.new(0, 0, 0)))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("Door", "Open", Vector3.new(10, 0, 0)), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].custom.distanceToPrompt).to.equal(10)
		end)

		it("distanceToPrompt is nil when prompt has no parent part", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("Door", "Open", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].custom.distanceToPrompt).to.equal(nil)
		end)

		it("maps Keyboard inputType to KeyboardAndMouse", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("", "Use", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].custom.inputType).to.equal("KeyboardAndMouse")
		end)

		it("includes player position", function()
			local pos         = Vector3.new(5, 0, 10)
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(pos))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("", "Use", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(handler.calls[1].position).to.equal(pos)
		end)

		it("fires independently for multiple different prompts", function()
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil))
			local handler     = makeHandler()

			setupProximityPromptShown(handler, svc)
			promptShown:Fire(makePrompt("A", "Use", nil), Enum.ProximityPromptInputType.Keyboard)
			promptShown:Fire(makePrompt("B", "Use", nil), Enum.ProximityPromptInputType.Keyboard)

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].custom.promptName).to.equal("A")
			expect(handler.calls[2].custom.promptName).to.equal("B")
		end)

	end)

	describe("ProximityPromptShown debounce", function()

		it("suppresses same prompt shown again within cooldown window", function()
			local time        = 0
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil), function() return time end)
			local handler     = makeHandler()
			local prompt      = makePrompt("Door", "Open", nil)

			setupProximityPromptShown(handler, svc)
			time = 0
			promptShown:Fire(prompt, Enum.ProximityPromptInputType.Keyboard)
			time = 1.5 -- within 2s cooldown
			promptShown:Fire(prompt, Enum.ProximityPromptInputType.Keyboard)

			expect(#handler.calls).to.equal(1)
		end)

		it("allows same prompt after cooldown expires", function()
			local time        = 0
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil), function() return time end)
			local handler     = makeHandler()
			local prompt      = makePrompt("Door", "Open", nil)

			setupProximityPromptShown(handler, svc)
			time = 0
			promptShown:Fire(prompt, Enum.ProximityPromptInputType.Keyboard)
			time = 2.1 -- past 2s cooldown
			promptShown:Fire(prompt, Enum.ProximityPromptInputType.Keyboard)

			expect(#handler.calls).to.equal(2)
		end)

		it("different prompts have independent cooldowns", function()
			local time        = 0
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil), function() return time end)
			local handler     = makeHandler()
			local promptA     = makePrompt("ChestA", "Open", nil)
			local promptB     = makePrompt("ChestB", "Open", nil)

			setupProximityPromptShown(handler, svc)
			time = 0
			promptShown:Fire(promptA, Enum.ProximityPromptInputType.Keyboard)
			time = 0.5 -- within promptA cooldown, but promptB has no prior fire
			promptShown:Fire(promptB, Enum.ProximityPromptInputType.Keyboard)

			expect(#handler.calls).to.equal(2)
		end)

		it("suppressing one prompt does not block others", function()
			local time        = 0
			local promptShown = makeSignal()
			local svc         = makeServices(promptShown, makeLocalPlayer(nil), function() return time end)
			local handler     = makeHandler()
			local promptA     = makePrompt("A", "Use", nil)
			local promptB     = makePrompt("B", "Use", nil)

			setupProximityPromptShown(handler, svc)
			time = 0
			promptShown:Fire(promptA, Enum.ProximityPromptInputType.Keyboard)
			time = 1.0
			promptShown:Fire(promptA, Enum.ProximityPromptInputType.Keyboard) -- suppressed
			promptShown:Fire(promptB, Enum.ProximityPromptInputType.Keyboard) -- different prompt, fires

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].custom.promptName).to.equal("A")
			expect(handler.calls[2].custom.promptName).to.equal("B")
		end)

	end)
end
