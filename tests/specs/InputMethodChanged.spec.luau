local ReplicatedStorage       = game:GetService("ReplicatedStorage")
local setupInputMethodChanged = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["input-method-changed"])

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
		Character = root and {
			FindFirstChild = function(_, name)
				if name == "HumanoidRootPart" then return root end
			end,
		} or nil,
	}
end

local function makeServices(lastInputChanged, localPlayer)
	return {
		UserInputService = { LastInputTypeChanged = lastInputChanged },
		Players          = { LocalPlayer = localPlayer },
	}
end

return function()
	describe("InputMethodChanged", function()

		it("fires InputMethodChanged on first input type seen", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("InputMethodChanged")
			expect(handler.calls[1].custom.fromInput).to.equal(nil)
			expect(handler.calls[1].custom.toInput).to.equal("KeyboardAndMouse")
		end)

		it("tracks category switch from KeyboardAndMouse to Touch", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)
			changed:Fire(Enum.UserInputType.Touch)

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].custom.fromInput).to.equal("KeyboardAndMouse")
			expect(handler.calls[2].custom.toInput).to.equal("Touch")
		end)

		it("tracks switch to Gamepad", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Gamepad1)

			expect(handler.calls[1].custom.toInput).to.equal("Gamepad")
		end)

		it("ignores unknown input types", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.None)

			expect(#handler.calls).to.equal(0)
		end)

		it("includes player position", function()
			local pos     = Vector3.new(3, 0, 7)
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(pos))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Touch)

			expect(handler.calls[1].position).to.equal(pos)
		end)

	end)

	describe("InputMethodChanged deduplication", function()

		it("does not fire when input switches within KeyboardAndMouse category", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)       -- nil → KBM  (fires)
			changed:Fire(Enum.UserInputType.MouseButton1)   -- KBM → KBM  (suppressed)
			changed:Fire(Enum.UserInputType.MouseButton2)   -- KBM → KBM  (suppressed)
			changed:Fire(Enum.UserInputType.MouseMovement)  -- KBM → KBM  (suppressed)
			changed:Fire(Enum.UserInputType.MouseWheel)     -- KBM → KBM  (suppressed)

			expect(#handler.calls).to.equal(1)
		end)

		it("does not fire when input switches within Gamepad category", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Gamepad1) -- nil → Gamepad (fires)
			changed:Fire(Enum.UserInputType.Gamepad2) -- Gamepad → Gamepad (suppressed)
			changed:Fire(Enum.UserInputType.Gamepad3) -- Gamepad → Gamepad (suppressed)
			changed:Fire(Enum.UserInputType.Gamepad4) -- Gamepad → Gamepad (suppressed)

			expect(#handler.calls).to.equal(1)
		end)

		it("fires on each genuine cross-category switch", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)  -- nil → KBM
			changed:Fire(Enum.UserInputType.Gamepad1)  -- KBM → Gamepad
			changed:Fire(Enum.UserInputType.Touch)      -- Gamepad → Touch
			changed:Fire(Enum.UserInputType.Keyboard)  -- Touch → KBM

			expect(#handler.calls).to.equal(4)
		end)

		it("records correct fromInput and toInput across switches", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Touch)
			changed:Fire(Enum.UserInputType.Gamepad1)

			expect(handler.calls[1].custom.fromInput).to.equal(nil)
			expect(handler.calls[1].custom.toInput).to.equal("Touch")
			expect(handler.calls[2].custom.fromInput).to.equal("Touch")
			expect(handler.calls[2].custom.toInput).to.equal("Gamepad")
		end)

		it("unknown types between valid types do not reset category", function()
			local changed = makeSignal()
			local handler = makeHandler()
			local svc     = makeServices(changed, makeLocalPlayer(nil))

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard) -- nil → KBM (fires)
			changed:Fire(Enum.UserInputType.None)     -- unknown, ignored
			changed:Fire(Enum.UserInputType.MouseButton1) -- still KBM, suppressed

			expect(#handler.calls).to.equal(1)
		end)

	end)
end
