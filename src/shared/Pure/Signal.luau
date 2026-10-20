--!strict
-- Minimal synchronous signal used by client state stores.
export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { any } }, Signal)
	return self :: any
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local conn = { Connected = true }
	function conn.Disconnect(c)
		if not c.Connected then
			return
		end
		c.Connected = false
		local i = table.find(handlers, fn)
		if i then
			table.remove(handlers, i)
		end
	end
	table.insert(handlers, fn)
	return conn
end

function Signal:Fire(...)
	for _, fn in table.clone(self._handlers) do
		(fn :: any)(...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
