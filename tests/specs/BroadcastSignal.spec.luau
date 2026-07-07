local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BroadcastSignal = require(ReplicatedStorage.RosaRbx.broadcast["broadcast-signal"])
local Constants = require(ReplicatedStorage.RosaRbx.broadcast.constants)

return function()
	describe("BroadcastSignal", function()

		describe("publishStart()", function()
			it("publishes to the start topic", function()
				local published = {}
				local messagingService = {
					PublishAsync = function(_, topic, message)
						table.insert(published, { topic = topic, message = message })
					end,
				}
				local signal = BroadcastSignal.new({ MessagingService = messagingService })
				signal:publishStart()
				expect(#published).to.equal(1)
				expect(published[1].topic).to.equal(Constants.MESSAGING_TOPIC_START)
			end)

			it("does not throw when PublishAsync fails", function()
				local messagingService = {
					PublishAsync = function()
						error("rate limited")
					end,
				}
				local signal = BroadcastSignal.new({ MessagingService = messagingService })
				expect(function()
					signal:publishStart()
				end).never.to.throw()
			end)
		end)

		describe("onStart()", function()
			it("subscribes to the start topic and forwards delivery to the callback", function()
				local handlers = {}
				local messagingService = {
					SubscribeAsync = function(_, topic, handler)
						handlers[topic] = handler
					end,
				}
				local signal = BroadcastSignal.new({ MessagingService = messagingService })

				local callCount = 0
				signal:onStart(function()
					callCount += 1
				end)

				expect(handlers[Constants.MESSAGING_TOPIC_START] ~= nil).to.equal(true)
				handlers[Constants.MESSAGING_TOPIC_START]({ Data = true, Sent = os.time() })
				expect(callCount).to.equal(1)
			end)

			it("does not throw when SubscribeAsync fails", function()
				local attempts = 0
				local messagingService = {
					SubscribeAsync = function()
						attempts += 1
						if attempts < 2 then
							error("not available")
						end
					end,
				}
				local signal = BroadcastSignal.new({ MessagingService = messagingService, wait = function() end })
				expect(function()
					signal:onStart(function() end)
				end).never.to.throw()
				expect(attempts).to.equal(2)
			end)

			it("retries SubscribeAsync with backoff until it succeeds", function()
				local handlers = {}
				local attempts = 0
				local messagingService = {
					SubscribeAsync = function(_, topic, handler)
						attempts += 1
						if attempts < 3 then
							error("not available")
						end
						handlers[topic] = handler
					end,
				}
				local waitedFor = {}
				local signal = BroadcastSignal.new({
					MessagingService = messagingService,
					wait = function(seconds) table.insert(waitedFor, seconds) end,
				})

				signal:onStart(function() end)

				expect(attempts).to.equal(3)
				expect(handlers[Constants.MESSAGING_TOPIC_START] ~= nil).to.equal(true)
				expect(waitedFor[1]).to.equal(0) -- backoffSeconds(0)
				expect(waitedFor[2]).to.equal(1) -- backoffSeconds(1)
			end)

			it("does not let a throwing callback break delivery of the next message", function()
				local handlers = {}
				local messagingService = {
					SubscribeAsync = function(_, topic, handler)
						handlers[topic] = handler
					end,
				}
				local signal = BroadcastSignal.new({ MessagingService = messagingService })

				local callCount = 0
				signal:onStart(function()
					callCount += 1
					if callCount == 1 then
						error("simulated callback failure")
					end
				end)

				local deliver = handlers[Constants.MESSAGING_TOPIC_START]
				expect(function()
					deliver({ Data = true, Sent = os.time() })
				end).never.to.throw()

				-- A second, independent delivery must still reach the callback.
				expect(function()
					deliver({ Data = true, Sent = os.time() })
				end).never.to.throw()

				expect(callCount).to.equal(2)
			end)
		end)

	end)
end
