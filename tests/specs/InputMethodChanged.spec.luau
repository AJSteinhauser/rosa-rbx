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

-- Fake `delay` records scheduled callbacks instead of waiting for real time.
-- settle() runs everything queued so far, matching what happens once the real
-- debounce window elapses.
local function makeDelay()
	local pending = {}
	return {
		delay = function(_, fn) table.insert(pending, fn) end,
		settle = function()
			local batch = pending
			pending = {}
			for _, fn in batch do fn() end
		end,
	}
end

local function makeServices(lastInputChanged, localPlayer, overrides)
	overrides = overrides or {}
	return {
		UserInputService = {
			LastInputTypeChanged  = lastInputChanged,
			TouchEnabled          = overrides.touchEnabled ~= false,
			GetConnectedGamepads  = overrides.getConnectedGamepads or function()
				return { Enum.UserInputType.Gamepad1 }
			end,
		},
		Players = { LocalPlayer = localPlayer },
		delay   = overrides.delay,
	}
end

return function()
	describe("InputMethodChanged", function()

		it("fires InputMethodChanged on first input type seen", function()
			local changed    = makeSignal()
			local handler    = makeHandler()
			local fakeDelay  = makeDelay()
			local svc        = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("InputMethodChanged")
			expect(handler.calls[1].custom.fromInput).to.equal(nil)
			expect(handler.calls[1].custom.toInput).to.equal("KeyboardAndMouse")
		end)

		it("tracks category switch from KeyboardAndMouse to Touch", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Touch)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].custom.fromInput).to.equal("KeyboardAndMouse")
			expect(handler.calls[2].custom.toInput).to.equal("Touch")
		end)

		it("tracks switch to Gamepad", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Gamepad1)
			fakeDelay.settle()

			expect(handler.calls[1].custom.toInput).to.equal("Gamepad")
		end)

		it("ignores unknown input types", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.None)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(0)
		end)

		it("includes player position", function()
			local pos       = Vector3.new(3, 0, 7)
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(pos), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Touch)
			fakeDelay.settle()

			expect(handler.calls[1].position).to.equal(pos)
		end)

	end)

	describe("InputMethodChanged deduplication", function()

		it("does not fire when input switches within KeyboardAndMouse category", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.MouseButton1)   -- KBM -> KBM (suppressed)
			changed:Fire(Enum.UserInputType.MouseButton2)   -- KBM -> KBM (suppressed)
			changed:Fire(Enum.UserInputType.MouseMovement)  -- KBM -> KBM (suppressed)
			changed:Fire(Enum.UserInputType.MouseWheel)     -- KBM -> KBM (suppressed)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
		end)

		it("does not fire when input switches within Gamepad category", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Gamepad1)
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Gamepad2) -- Gamepad -> Gamepad (suppressed)
			changed:Fire(Enum.UserInputType.Gamepad3) -- Gamepad -> Gamepad (suppressed)
			changed:Fire(Enum.UserInputType.Gamepad4) -- Gamepad -> Gamepad (suppressed)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
		end)

		it("fires on each genuine cross-category switch that settles", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)  -- nil -> KBM
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Gamepad1)  -- KBM -> Gamepad
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Touch)     -- Gamepad -> Touch
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Keyboard)  -- Touch -> KBM
			fakeDelay.settle()

			expect(#handler.calls).to.equal(4)
		end)

		it("records correct fromInput and toInput across switches", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Touch)
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.Gamepad1)
			fakeDelay.settle()

			expect(handler.calls[1].custom.fromInput).to.equal(nil)
			expect(handler.calls[1].custom.toInput).to.equal("Touch")
			expect(handler.calls[2].custom.fromInput).to.equal("Touch")
			expect(handler.calls[2].custom.toInput).to.equal("Gamepad")
		end)

		it("unknown types between valid types do not reset category", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard) -- nil -> KBM (fires)
			fakeDelay.settle()
			changed:Fire(Enum.UserInputType.None)         -- unknown, ignored
			changed:Fire(Enum.UserInputType.MouseButton1) -- still KBM, suppressed
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
		end)

	end)

	describe("InputMethodChanged debounce", function()

		it("collapses a rapid flap back to the original category into zero events", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard) -- nil -> KBM (fires)
			fakeDelay.settle()

			-- Phantom Gamepad blip that reverts before the debounce window closes:
			-- both scheduled checks should see it never actually settled on Gamepad.
			changed:Fire(Enum.UserInputType.Gamepad1) -- KBM -> Gamepad (pending)
			changed:Fire(Enum.UserInputType.Keyboard) -- Gamepad -> KBM (pending, supersedes)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
		end)

		it("only commits the category that was current when the window closed", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), { delay = fakeDelay.delay })

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard) -- nil -> KBM
			fakeDelay.settle()

			changed:Fire(Enum.UserInputType.Gamepad1) -- KBM -> Gamepad (superseded)
			changed:Fire(Enum.UserInputType.Touch)    -- Gamepad -> Touch (settles)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].custom.fromInput).to.equal("KeyboardAndMouse")
			expect(handler.calls[2].custom.toInput).to.equal("Touch")
		end)

	end)

	describe("InputMethodChanged plausibility guard", function()

		it("ignores Touch reports when the device has no touch digitizer", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), {
				delay        = fakeDelay.delay,
				touchEnabled = false,
			})

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Touch)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(0)
		end)

		it("ignores Gamepad reports when no gamepad is connected", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), {
				delay                = fakeDelay.delay,
				getConnectedGamepads = function() return {} end,
			})

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Gamepad1)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(0)
		end)

		it("always allows KeyboardAndMouse regardless of connected-device checks", function()
			local changed   = makeSignal()
			local handler   = makeHandler()
			local fakeDelay = makeDelay()
			local svc       = makeServices(changed, makeLocalPlayer(nil), {
				delay                = fakeDelay.delay,
				touchEnabled         = false,
				getConnectedGamepads = function() return {} end,
			})

			setupInputMethodChanged(handler, svc)
			changed:Fire(Enum.UserInputType.Keyboard)
			fakeDelay.settle()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].custom.toInput).to.equal("KeyboardAndMouse")
		end)

	end)
end
