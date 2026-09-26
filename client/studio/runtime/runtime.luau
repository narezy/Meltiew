--!nocheck
-- Meltiew runtime: the object model scripts see (game, workspace, Instance.new, events,
-- task.wait, remotes, UI...). It runs inside the sandboxed Luau VM on both the game
-- server and every client, loaded before any user script (chunk name "=runtime").
--
-- The host (Node on the server, Godot on clients) talks to it through four globals,
-- each taking and returning a JSON string:
--   __init(cfg)      build the tree from a place, set the role (server / client)
--   __start(_)       run the scripts
--   __dispatch(evs)  things that happened outside (network, input, touches...)
--   __step(t)        advance time: Heartbeat, task.wait, tweens
-- Every call returns the list of operations the host must apply (tree changes,
-- remote calls, prints). See docs/studio/runtime.md.

local compile = __compile
local clock = __clock

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local json = {}
do
	local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
	local function escapeStr(s)
		return '"' .. string.gsub(s, '[%c"\\]', function(c)
			return escapes[c] or string.format("\\u%04x", string.byte(c))
		end) .. '"'
	end
	local function isArray(t)
		local n = #t
		if n == 0 then
			return next(t) == nil and t.__array == true
		end
		for k in t do
			if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
				return false
			end
		end
		return true
	end
	local encode
	function encode(v, out)
		local tv = type(v)
		if v == nil then
			out[#out + 1] = "null"
		elseif tv == "boolean" then
			out[#out + 1] = v and "true" or "false"
		elseif tv == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				out[#out + 1] = "0"
			elseif v % 1 == 0 and math.abs(v) < 1e15 then
				out[#out + 1] = string.format("%d", v)
			else
				out[#out + 1] = string.format("%.14g", v)
			end
		elseif tv == "string" then
			out[#out + 1] = escapeStr(v)
		elseif tv == "table" then
			if isArray(v) then
				out[#out + 1] = "["
				for i = 1, #v do
					if i > 1 then
						out[#out + 1] = ","
					end
					encode(v[i], out)
				end
				out[#out + 1] = "]"
			else
				out[#out + 1] = "{"
				local first = true
				for k, val in v do
					if k ~= "__array" then
						if not first then
							out[#out + 1] = ","
						end
						first = false
						out[#out + 1] = escapeStr(tostring(k))
						out[#out + 1] = ":"
						encode(val, out)
					end
				end
				out[#out + 1] = "}"
			end
		else
			out[#out + 1] = "null"
		end
	end
	function json.encode(v)
		local out = {}
		encode(v, out)
		return table.concat(out)
	end

	local function decodeError(str, pos, msg)
		error(string.format("json: %s at %d", msg, pos), 0)
	end
	local decodeValue
	local function skip(str, pos)
		return string.find(str, "[^ \t\r\n]", pos) or #str + 1
	end
	local function decodeString(str, pos)
		local out = {}
		local i = pos + 1
		while true do
			local c = string.sub(str, i, i)
			if c == "" then
				decodeError(str, i, "unterminated string")
			elseif c == '"' then
				return table.concat(out), i + 1
			elseif c == "\\" then
				local e = string.sub(str, i + 1, i + 1)
				if e == "u" then
					local code = tonumber(string.sub(str, i + 2, i + 5), 16) or 63
					if code >= 0xD800 and code <= 0xDBFF and string.sub(str, i + 6, i + 7) == "\\u" then
						local low = tonumber(string.sub(str, i + 8, i + 11), 16) or 0
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						i = i + 6
					end
					out[#out + 1] = utf8.char(code)
					i = i + 6
				else
					local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
					out[#out + 1] = map[e] or e
					i = i + 2
				end
			else
				local j = string.find(str, '["\\]', i) or #str + 1
				out[#out + 1] = string.sub(str, i, j - 1)
				i = j
			end
		end
	end
	function decodeValue(str, pos)
		pos = skip(str, pos)
		local c = string.sub(str, pos, pos)
		if c == "{" then
			local obj = {}
			pos = skip(str, pos + 1)
			if string.sub(str, pos, pos) == "}" then
				return obj, pos + 1
			end
			while true do
				pos = skip(str, pos)
				local key
				key, pos = decodeString(str, pos)
				pos = skip(str, pos)
				if string.sub(str, pos, pos) ~= ":" then
					decodeError(str, pos, "expected ':'")
				end
				local val
				val, pos = decodeValue(str, pos + 1)
				obj[key] = val
				pos = skip(str, pos)
				local d = string.sub(str, pos, pos)
				if d == "}" then
					return obj, pos + 1
				elseif d ~= "," then
					decodeError(str, pos, "expected ',' or '}'")
				end
				pos = pos + 1
			end
		elseif c == "[" then
			local arr = { __array = true }
			pos = skip(str, pos + 1)
			if string.sub(str, pos, pos) == "]" then
				return arr, pos + 1
			end
			local n = 0
			while true do
				local val
				val, pos = decodeValue(str, pos)
				n = n + 1
				arr[n] = val
				pos = skip(str, pos)
				local d = string.sub(str, pos, pos)
				if d == "]" then
					arr.__array = nil
					return arr, pos + 1
				elseif d ~= "," then
					decodeError(str, pos, "expected ',' or ']'")
				end
				pos = pos + 1
			end
		elseif c == '"' then
			return decodeString(str, pos)
		elseif string.sub(str, pos, pos + 3) == "true" then
			return true, pos + 4
		elseif string.sub(str, pos, pos + 4) == "false" then
			return false, pos + 5
		elseif string.sub(str, pos, pos + 3) == "null" then
			return nil, pos + 4
		else
			local num = string.match(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not num or num == "" then
				decodeError(str, pos, "unexpected character")
			end
			return tonumber(num), pos + #num
		end
	end
	function json.decode(str)
		local v = decodeValue(str, 1)
		return v
	end
	-- An empty array that still encodes as [].
	function json.array()
		return { __array = true }
	end
end

---------------------------------------------------------------------------
-- Data types (immutable values, same names as the scripting API)
---------------------------------------------------------------------------
local function round3(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

local Vector3 = {}
local V3mt = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
local function isV3(v)
	return getmetatable(v) == V3mt
end
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" or k == "y" or k == "z" then
		return rawget(v, string.upper(k))
	end
	return Vector3[k]
end
V3mt.__newindex = function()
	error("Vector3 is read-only; make a new one with Vector3.new", 2)
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(v)
	return string.format("%g, %g, %g", round3(v.X), round3(v.Y), round3(v.Z))
end
function Vector3.new(x, y, z)
	return v3(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function Vector3.Distance(a, b)
	return (a - b).Magnitude
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

local Vector2 = {}
local V2mt = { __type = "Vector2" }
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2mt)
end
V2mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "x" or k == "y" then
		return rawget(v, string.upper(k))
	end
	return Vector2[k]
end
V2mt.__newindex = function()
	error("Vector2 is read-only", 2)
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2mt.__tostring = function(v)
	return string.format("%g, %g", round3(v.X), round3(v.Y))
end
function Vector2.new(x, y)
	return v2(tonumber(x) or 0, tonumber(y) or 0)
end
function Vector2.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
Vector2.zero = v2(0, 0)

local Color3 = {}
local C3mt = { __type = "Color3" }
local function c3(r, g, b)
	return setmetatable({ R = math.clamp(r, 0, 1), G = math.clamp(g, 0, 1), B = math.clamp(b, 0, 1) }, C3mt)
end
C3mt.__index = function(c, k)
	if k == "r" or k == "g" or k == "b" then
		return rawget(c, string.upper(k))
	end
	return Color3[k]
end
C3mt.__newindex = function()
	error("Color3 is read-only", 2)
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3mt.__tostring = function(c)
	return Color3.ToHex(c)
end
function Color3.new(r, g, b)
	return c3(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0)
end
function Color3.fromRGB(r, g, b)
	return c3((tonumber(r) or 0) / 255, (tonumber(g) or 0) / 255, (tonumber(b) or 0) / 255)
end
function Color3.fromHex(hex)
	hex = string.gsub(tostring(hex), "#", "")
	if #hex == 3 then
		hex = string.gsub(hex, ".", "%0%0")
	end
	local r = tonumber(string.sub(hex, 1, 2), 16) or 0
	local g = tonumber(string.sub(hex, 3, 4), 16) or 0
	local b = tonumber(string.sub(hex, 5, 6), 16) or 0
	return c3(r / 255, g / 255, b / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return c3(v, t, p)
	elseif m == 1 then
		return c3(q, v, p)
	elseif m == 2 then
		return c3(p, v, t)
	elseif m == 3 then
		return c3(p, q, v)
	elseif m == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
function Color3.ToHex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
function Color3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local UDim = {}
local Umt = { __type = "UDim" }
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, Umt)
end
Umt.__index = UDim
Umt.__newindex = function()
	error("UDim is read-only", 2)
end
Umt.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
Umt.__tostring = function(u)
	return string.format("%g, %g", u.Scale, u.Offset)
end
function UDim.new(s, o)
	return udim(tonumber(s) or 0, tonumber(o) or 0)
end

local UDim2 = {}
local U2mt = { __type = "UDim2" }
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2mt)
end
U2mt.__index = function(u, k)
	if k == "Width" then
		return rawget(u, "X")
	elseif k == "Height" then
		return rawget(u, "Y")
	end
	return UDim2[k]
end
U2mt.__newindex = function()
	error("UDim2 is read-only", 2)
end
U2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
U2mt.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2mt.__tostring = function(u)
	return string.format("{%g, %g}, {%g, %g}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
function UDim2.new(xs, xo, ys, yo)
	return udim2(tonumber(xs) or 0, tonumber(xo) or 0, tonumber(ys) or 0, tonumber(yo) or 0)
end
function UDim2.fromScale(x, y)
	return udim2(tonumber(x) or 0, 0, tonumber(y) or 0, 0)
end
function UDim2.fromOffset(x, y)
	return udim2(0, tonumber(x) or 0, 0, tonumber(y) or 0)
end
function UDim2.Lerp(a, b, t)
	local function l(p, q)
		return p + (q - p) * t
	end
	return udim2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end

local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return table.freeze({
		Time = tonumber(time) or 1,
		EasingStyle = style or "Quad",
		EasingDirection = direction or "Out",
		RepeatCount = tonumber(repeatCount) or 0,
		Reverses = reverses == true,
		DelayTime = tonumber(delayTime) or 0,
	})
end

local function typeOf(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and rawget(mt, "__type") then
		return mt.__type
	end
	return type(v)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local role = "server" -- "server" or "client"
local schema = nil
local classes = {} -- name -> { name, base, props (with inherited), events (set), isA (set), info }
local enums = {}
local byId = {} -- id -> instance
local D = {} -- instance -> internal data
local nextId = 1
local idPrefix = ""
local simTime = 0
local started = false
local localUserId = nil
local playerLang = "en"
local stringsTable = {}
local ops = {} -- operations for the host, flushed at the end of every call
local setIndex = {} -- id -> { prop -> index in ops }
local report -- forward: prints an error with the script's name

local function emit(op)
	ops[#ops + 1] = op
end

local function flush()
	local out = ops
	ops = {}
	setIndex = {}
	if #out == 0 then
		return "[]"
	end
	return json.encode(out)
end

---------------------------------------------------------------------------
-- Scheduler: every script, event handler and task runs in its own coroutine
---------------------------------------------------------------------------
local waiting = {} -- { co, at, started }
local deferred = {}
local threadScript = setmetatable({}, { __mode = "k" }) -- co -> script instance (for errors)
local currentScript = nil

local function resume(co, ...)
	local prev = currentScript
	currentScript = threadScript[co]
	local ok, err = coroutine.resume(co, ...)
	currentScript = prev
	if not ok then
		report(debug.traceback(co, tostring(err)), threadScript[co])
	end
	return ok
end

local function spawnFn(fn, ...)
	local co = coroutine.create(fn)
	threadScript[co] = currentScript
	resume(co, ...)
	return co
end

local task = {}
function task.wait(t)
	local co = coroutine.running()
	t = tonumber(t) or 0
	local entry = { co = co, at = simTime + math.max(t, 0), started = simTime }
	waiting[#waiting + 1] = entry
	return coroutine.yield()
end
function task.spawn(fn, ...)
	if type(fn) == "thread" then
		resume(fn, ...)
		return fn
	end
	return spawnFn(fn, ...)
end
function task.defer(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	if type(fn) ~= "thread" then
		threadScript[co] = currentScript
	end
	deferred[#deferred + 1] = { co = co, args = table.pack(...) }
	return co
end
function task.delay(t, fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		task.wait(t)
		fn(table.unpack(args, 1, args.n))
	end)
	threadScript[co] = currentScript
	resume(co)
	return co
end
function task.cancel(co)
	for i = #waiting, 1, -1 do
		if waiting[i].co == co then
			table.remove(waiting, i)
		end
	end
	pcall(coroutine.close, co)
end

local function runDeferred()
	local rounds = 0
	while #deferred > 0 and rounds < 20 do
		rounds += 1
		local list = deferred
		deferred = {}
		for _, d in list do
			if coroutine.status(d.co) == "suspended" then
				resume(d.co, table.unpack(d.args, 1, d.args.n))
			end
		end
	end
end

local function runWaiting()
	if #waiting == 0 then
		return
	end
	local due = {}
	local keep = {}
	for _, w in waiting do
		if w.at <= simTime then
			due[#due + 1] = w
		else
			keep[#keep + 1] = w
		end
	end
	waiting = keep
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, w in due do
		if coroutine.status(w.co) == "suspended" then
			resume(w.co, simTime - w.started)
		end
	end
end

---------------------------------------------------------------------------
-- Signals (events): :Connect, :Once, :Wait
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
Signal.__type = "RBXScriptSignal"
local Connection = {}
Connection.__index = Connection

function Signal.new(name)
	return setmetatable({ _handlers = {}, _waiting = {}, _name = name }, Signal)
end
function Signal:Connect(fn)
	if type(fn) ~= "function" then
		error("Connect needs a function", 2)
	end
	local c = setmetatable({ Connected = true, _signal = self, _fn = fn, _script = currentScript }, Connection)
	table.insert(self._handlers, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	local co = coroutine.running()
	table.insert(self._waiting, co)
	return coroutine.yield()
end
function Signal:_fire(...)
	local handlers = table.clone(self._handlers)
	for _, c in handlers do
		if c.Connected then
			local co = coroutine.create(c._fn)
			threadScript[co] = c._script
			resume(co, ...)
		end
	end
	if #self._waiting > 0 then
		local list = self._waiting
		self._waiting = {}
		for _, co in list do
			if coroutine.status(co) == "suspended" then
				resume(co, ...)
			end
		end
	end
end
function Signal:_clear()
	for _, c in self._handlers do
		c.Connected = false
	end
	self._handlers = {}
end
function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._handlers
	for i, c in list do
		if c == self then
			table.remove(list, i)
			break
		end
	end
end
Connection.disconnect = Connection.Disconnect
Signal.connect = Signal.Connect
Signal.wait = Signal.Wait

---------------------------------------------------------------------------
-- Values <-> JSON (properties, remote arguments, places)
-- Vector3 {"$v3":[x,y,z]}, Vector2 {"$v2":[x,y]}, Color3 {"$c3":"#rrggbb"},
-- UDim2 {"$u2":[xs,xo,ys,yo]}, UDim {"$u":[s,o]}, Instance {"$i":"id"}
---------------------------------------------------------------------------
local InstMT -- forward
local function isInstance(v)
	return type(v) == "table" and getmetatable(v) == InstMT
end

local function encodeValue(v, depth)
	local t = typeOf(v)
	if t == "Vector3" then
		return { ["$v3"] = { v.X, v.Y, v.Z } }
	elseif t == "Vector2" then
		return { ["$v2"] = { v.X, v.Y } }
	elseif t == "Color3" then
		return { ["$c3"] = Color3.ToHex(v) }
	elseif t == "UDim2" then
		return { ["$u2"] = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "UDim" then
		return { ["$u"] = { v.Scale, v.Offset } }
	elseif isInstance(v) then
		return { ["$i"] = D[v].id }
	elseif t == "table" then
		depth = (depth or 0) + 1
		if depth > 8 then
			return nil
		end
		local out = {}
		local n = 0
		for k, val in v do
			n += 1
			if n > 1000 then
				break
			end
			local kt = type(k)
			if kt == "string" or kt == "number" then
				out[k] = encodeValue(val, depth)
			end
		end
		return out
	elseif t == "number" or t == "string" or t == "boolean" or t == "nil" then
		return v
	end
	return nil
end

local function decodeValue(v, depth)
	if type(v) ~= "table" then
		return v
	end
	if v["$v3"] then
		local a = v["$v3"]
		return v3(a[1] or 0, a[2] or 0, a[3] or 0)
	elseif v["$v2"] then
		local a = v["$v2"]
		return v2(a[1] or 0, a[2] or 0)
	elseif v["$c3"] then
		local c = v["$c3"]
		if type(c) == "table" then
			return c3(c[1] or 0, c[2] or 0, c[3] or 0)
		end
		return Color3.fromHex(c)
	elseif v["$u2"] then
		local a = v["$u2"]
		return udim2(a[1] or 0, a[2] or 0, a[3] or 0, a[4] or 0)
	elseif v["$u"] then
		local a = v["$u"]
		return udim(a[1] or 0, a[2] or 0)
	elseif v["$i"] then
		return byId[v["$i"]]
	end
	depth = (depth or 0) + 1
	if depth > 8 then
		return nil
	end
	local out = {}
	for k, val in v do
		if k ~= "__array" then
			out[k] = decodeValue(val, depth)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Classes (from classes.json, shared with Studio and the renderers)
---------------------------------------------------------------------------
local Methods = {} -- class name -> { method name -> function }

local function buildClasses(s)
	schema = s
	enums = s.enums or {}
	local raw = s.classes
	local function build(name)
		if classes[name] then
			return classes[name]
		end
		local r = raw[name]
		if not r then
			return nil
		end
		local info = { name = name, props = {}, events = {}, isA = { [name] = true }, raw = r }
		if r.base then
			local b = build(r.base)
			for k, p in b.props do
				info.props[k] = p
			end
			for k in b.events do
				info.events[k] = true
			end
			for k in b.isA do
				info.isA[k] = true
			end
			info.base = b
		end
		for k, p in r.props or {} do
			info.props[k] = p
		end
		for _, e in r.events or {} do
			info.events[e] = true
		end
		-- Per-class defaults (SpawnLocation is bigger and mint, etc.).
		info.overrides = r.overrides or {}
		classes[name] = info
		return info
	end
	for name in raw do
		build(name)
	end
end

local function defaultOf(info, key)
	local o = info.overrides[key]
	if o ~= nil then
		return decodeValue(o)
	end
	local p = info.props[key]
	if p then
		return decodeValue(p.default)
	end
	return nil
end

-- Converts what a script assigned into the property's type, or errors with a clear message.
local function coerce(info, key, p, v)
	local t = p.type
	if t == "number" then
		local n = tonumber(v)
		if n == nil then
			error(string.format("%s.%s must be a number", info.name, key), 3)
		end
		if p.min and n < p.min then
			n = p.min
		end
		if p.max and n > p.max then
			n = p.max
		end
		return n
	elseif t == "string" or t == "source" or t == "asset" then
		if v == nil then
			return ""
		end
		return tostring(v)
	elseif t == "bool" then
		return v == true
	elseif t == "Instance" then
		if v ~= nil and not isInstance(v) then
			error(string.format("%s.%s must be an Instance", info.name, key), 3)
		end
		return v
	elseif string.sub(t, 1, 5) == "enum:" then
		local list = enums[string.sub(t, 6)] or {}
		v = tostring(v)
		for _, item in list do
			if item == v then
				return v
			end
		end
		error(string.format("%s.%s must be one of: %s", info.name, key, table.concat(list, ", ")), 3)
	else
		if typeOf(v) ~= t then
			error(string.format("%s.%s must be a %s (e.g. %s.new(...)), got %s", info.name, key, t, t, typeOf(v)), 3)
		end
		return v
	end
end

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------
local Instance = {}
local DataModel -- the root (id "0")
local services = {}

InstMT = { __type = "Instance" }

local function newId()
	local id = idPrefix .. tostring(nextId)
	nextId += 1
	return id
end

local function create(className, id)
	local info = classes[className]
	if not info then
		error("unknown class " .. tostring(className), 3)
	end
	local inst = setmetatable({}, InstMT)
	id = id or newId()
	D[inst] = {
		id = id,
		class = info,
		name = className,
		props = {},
		children = {},
		parent = nil,
		signals = {},
		propSignals = {},
	}
	for k, p in info.props do
		if k ~= "Name" then
			D[inst].props[k] = defaultOf(info, k)
		end
	end
	byId[id] = inst
	return inst
end

local function getSignal(inst, name)
	local d = D[inst]
	local s = d.signals[name]
	if not s then
		s = Signal.new(name)
		d.signals[name] = s
	end
	return s
end

local function fireEvent(inst, name, ...)
	local s = D[inst] and D[inst].signals[name]
	if s then
		s:_fire(...)
	end
end

-- Where an instance lives decides who hears about it:
-- the server replicates everything under the DataModel except server-only services
-- and Scripts; a client renders everything under its DataModel.
local serverOnly = { ServerScriptService = true, ServerStorage = true }
local function inScope(inst)
	local d = D[inst]
	if not d then
		return false
	end
	if role == "server" and (d.class.name == "Script") then
		return false
	end
	local cur = inst
	while cur do
		local cd = D[cur]
		if cur == DataModel then
			return true
		end
		if role == "server" and cd.parent == DataModel and serverOnly[cd.class.name] then
			return false
		end
		cur = cd.parent
	end
	return false
end

-- Properties the renderer never needs are kept off the wire.
local function wireProps(inst)
	local d = D[inst]
	local out = {}
	for k, v in d.props do
		local p = d.class.props[k]
		if p and not (p.type == "source" and d.class.name == "Script") then
			local def = defaultOf(d.class, k)
			if v ~= def and v ~= nil then
				out[k] = encodeValue(v)
			end
		end
	end
	return out
end

local function emitNew(inst)
	local d = D[inst]
	emit({ o = "new", id = d.id, parent = d.parent and D[d.parent].id or nil, c = d.class.name, n = d.name, p = wireProps(inst) })
	for _, ch in d.children do
		if inScope(ch) then
			emitNew(ch)
		end
	end
end

local function emitSet(inst, key, value)
	local d = D[inst]
	local idx = setIndex[d.id] and setIndex[d.id][key]
	local v = encodeValue(value)
	if idx then
		ops[idx].v = v
		return
	end
	emit({ o = "set", id = d.id, k = key, v = v })
	setIndex[d.id] = setIndex[d.id] or {}
	setIndex[d.id][key] = #ops
end

local function firePropChanged(inst, key)
	local d = D[inst]
	fireEvent(inst, "Changed", key)
	local ps = d.propSignals[key]
	if ps then
		ps:_fire()
	end
end

local propHooks = {} -- class name -> { prop -> fn(inst) }

-- Internal property write. silent = don't tell the host (used for facts the host
-- already knows, like a player's own position).
local function setProp(inst, key, value, silent)
	local d = D[inst]
	if d.props[key] == value then
		return
	end
	d.props[key] = value
	if not silent and inScope(inst) then
		emitSet(inst, key, value)
	end
	firePropChanged(inst, key)
	local hooks = propHooks[d.class.name]
	if hooks and hooks[key] then
		hooks[key](inst)
	end
end

local startScriptsIn -- forward: runs scripts that just became runnable
local toolMouse -- forward: the client's Mouse, handed to Tool.Equipped

-- A character is a Model with a Humanoid in it; a Tool inside one is being held.
local function isCharacter(m)
	local d = m and D[m]
	if not d or d.class.name ~= "Model" then
		return false
	end
	for _, ch in d.children do
		if D[ch].class.name == "Humanoid" then
			return true
		end
	end
	return false
end

local function setParent(inst, parent)
	local d = D[inst]
	if d.destroyed then
		error("can't set the Parent of a destroyed " .. d.class.name, 3)
	end
	if parent == d.parent then
		return
	end
	if parent ~= nil then
		if not isInstance(parent) then
			error("Parent must be an Instance or nil", 3)
		end
		local cur = parent
		while cur do
			if cur == inst then
				error("can't make an instance its own ancestor", 3)
			end
			cur = D[cur].parent
		end
	end
	local before = inScope(inst)
	local old = d.parent
	if old then
		local list = D[old].children
		for i, ch in list do
			if ch == inst then
				table.remove(list, i)
				break
			end
		end
	end
	d.parent = parent
	if parent then
		table.insert(D[parent].children, inst)
	end
	local after = inScope(inst)
	if before and not after then
		emit({ o = "del", id = d.id })
	elseif after and not before then
		emitNew(inst)
	elseif after and before then
		emit({ o = "parent", id = d.id, parent = D[parent].id })
	end
	if old then
		fireEvent(old, "ChildRemoved", inst)
	end
	if parent then
		fireEvent(parent, "ChildAdded", inst)
	end
	fireEvent(inst, "AncestryChanged", inst, parent)
	firePropChanged(inst, "Parent")
	if parent and started then
		startScriptsIn(inst)
	end
	if d.class.name == "Tool" and old ~= parent then
		if isCharacter(old) then
			fireEvent(inst, "Unequipped")
		end
		if isCharacter(parent) then
			fireEvent(inst, "Equipped", role == "client" and toolMouse or nil)
		end
	end
end

local function getFullName(inst)
	local parts = {}
	local cur = inst
	while cur and cur ~= DataModel do
		table.insert(parts, 1, D[cur].name)
		cur = D[cur].parent
	end
	return table.concat(parts, ".")
end

local function destroy(inst)
	local d = D[inst]
	if not d or d.destroyed then
		return
	end
	fireEvent(inst, "Destroying")
	for i = #d.children, 1, -1 do
		destroy(d.children[i])
	end
	if d.parent then
		setParent(inst, nil)
	end
	d.destroyed = true
	for _, s in d.signals do
		s:_clear()
	end
	byId[d.id] = nil
	if d.onDestroy then
		d.onDestroy()
	end
end

local function clone(inst)
	local d = D[inst]
	local copy = create(d.class.name)
	local cd = D[copy]
	cd.name = d.name
	for k, v in d.props do
		cd.props[k] = v
	end
	for _, ch in d.children do
		local c = clone(ch)
		D[c].parent = copy
		table.insert(cd.children, c)
	end
	return copy
end

local function findMethod(info, key)
	local cur = info
	while cur do
		local m = Methods[cur.name]
		if m and m[key] ~= nil then
			return m[key]
		end
		cur = cur.base
	end
	return nil
end

local function findChild(inst, name)
	for _, ch in D[inst].children do
		if D[ch].name == name then
			return ch
		end
	end
	return nil
end

InstMT.__index = function(inst, key)
	local d = D[inst]
	if not d then
		error("this Instance was destroyed", 2)
	end
	if key == "Name" then
		return d.name
	elseif key == "Parent" then
		return d.parent
	elseif key == "ClassName" then
		return d.class.name
	end
	local v = d.props[key]
	if v ~= nil then
		return v
	end
	if d.class.props[key] then
		return nil
	end
	if d.class.events[key] then
		return getSignal(inst, key)
	end
	local m = findMethod(d.class, key)
	if m ~= nil then
		return m
	end
	if d.extra and d.extra[key] ~= nil then
		return d.extra[key]
	end
	local ch = findChild(inst, key)
	if ch then
		return ch
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), d.class.name, getFullName(inst)), 2)
end

InstMT.__newindex = function(inst, key, value)
	local d = D[inst]
	if not d then
		error("this Instance was destroyed", 2)
	end
	if key == "Name" then
		value = tostring(value)
		if d.name ~= value then
			d.name = value
			if inScope(inst) then
				emitSet(inst, "Name", value)
			end
			firePropChanged(inst, "Name")
		end
		return
	elseif key == "Parent" then
		setParent(inst, value)
		return
	end
	local p = d.class.props[key]
	if p then
		if p.readonly then
			error(string.format("%s.%s can't be changed by scripts", d.class.name, key), 2)
		end
		setProp(inst, key, coerce(d.class, key, p, value))
		return
	end
	-- Callbacks such as RemoteFunction.OnServerInvoke.
	local cb = d.class.raw.callbacks
	if cb and table.find(cb, key) then
		d.extra = d.extra or {}
		d.extra[key] = value
		return
	end
	error(string.format("%s is not a valid member of %s", tostring(key), d.class.name), 2)
end

InstMT.__tostring = function(inst)
	local d = D[inst]
	return d and d.name or "<destroyed>"
end

local function descendants(inst, out)
	for _, ch in D[inst].children do
		out[#out + 1] = ch
		descendants(ch, out)
	end
	return out
end

Methods.Instance = {
	FindFirstChild = function(self, name, recursive)
		if recursive then
			for _, ch in descendants(self, {}) do
				if D[ch].name == name then
					return ch
				end
			end
			return nil
		end
		return findChild(self, name)
	end,
	FindFirstChildOfClass = function(self, className)
		for _, ch in D[self].children do
			if D[ch].class.name == className then
				return ch
			end
		end
		return nil
	end,
	FindFirstChildWhichIsA = function(self, className, recursive)
		local list = recursive and descendants(self, {}) or D[self].children
		for _, ch in list do
			if D[ch].class.isA[className] then
				return ch
			end
		end
		return nil
	end,
	FindFirstAncestor = function(self, name)
		local cur = D[self].parent
		while cur do
			if D[cur].name == name then
				return cur
			end
			cur = D[cur].parent
		end
		return nil
	end,
	FindFirstAncestorOfClass = function(self, className)
		local cur = D[self].parent
		while cur do
			if D[cur].class.name == className then
				return cur
			end
			cur = D[cur].parent
		end
		return nil
	end,
	FindFirstAncestorWhichIsA = function(self, className)
		local cur = D[self].parent
		while cur do
			if D[cur].class.isA[className] then
				return cur
			end
			cur = D[cur].parent
		end
		return nil
	end,
	WaitForChild = function(self, name, timeout)
		local found = findChild(self, name)
		if found then
			return found
		end
		local limit = tonumber(timeout)
		local start = simTime
		local warned = false
		while true do
			task.wait()
			found = D[self] and findChild(self, name)
			if found then
				return found
			end
			if limit and simTime - start >= limit then
				return nil
			end
			if not limit and not warned and simTime - start > 5 then
				warned = true
				emit({ o = "print", level = "warn", msg = string.format('Still waiting for "%s" in %s', name, getFullName(self)) })
			end
		end
	end,
	GetChildren = function(self)
		return table.clone(D[self].children)
	end,
	GetDescendants = function(self)
		return descendants(self, {})
	end,
	IsA = function(self, className)
		return D[self].class.isA[className] == true
	end,
	IsDescendantOf = function(self, other)
		local cur = D[self].parent
		while cur do
			if cur == other then
				return true
			end
			cur = D[cur].parent
		end
		return false
	end,
	IsAncestorOf = function(self, other)
		return isInstance(other) and Methods.Instance.IsDescendantOf(other, self)
	end,
	GetFullName = function(self)
		return getFullName(self)
	end,
	Destroy = function(self)
		if D[self].class.raw.service or D[self].class.name == "Player" then
			error("can't destroy " .. D[self].class.name, 2)
		end
		destroy(self)
	end,
	Remove = function(self)
		setParent(self, nil)
	end,
	Clone = function(self)
		if D[self].class.raw.service or D[self].class.raw.runtime then
			error("can't clone " .. D[self].class.name, 2)
		end
		return clone(self)
	end,
	ClearAllChildren = function(self)
		for _, ch in table.clone(D[self].children) do
			if not D[ch].class.raw.service then
				destroy(ch)
			end
		end
	end,
	GetPropertyChangedSignal = function(self, prop)
		local d = D[self]
		local s = d.propSignals[prop]
		if not s then
			s = Signal.new(prop)
			d.propSignals[prop] = s
		end
		return s
	end,
	SetAttribute = function(self, name, value)
		local d = D[self]
		d.attributes = d.attributes or {}
		d.attributes[tostring(name)] = value
		fireEvent(self, "Changed", tostring(name))
	end,
	GetAttribute = function(self, name)
		local d = D[self]
		return d.attributes and d.attributes[tostring(name)]
	end,
}

local creatable = function(name)
	local info = classes[name]
	return info and info.raw.creatable == true
end

function Instance.new(className, parent)
	if not creatable(className) then
		error(string.format("can't create a %s with Instance.new", tostring(className)), 2)
	end
	local inst = create(className)
	if parent ~= nil then
		setParent(inst, parent)
	end
	return inst
end

-- Enum.Material.Neon == "Neon": enum values are plain strings, so both work.
local Enum = setmetatable({}, {
	__index = function(_, name)
		local list = enums[name]
		if not list then
			error("no enum named " .. tostring(name), 2)
		end
		local t = {}
		for _, v in list do
			t[v] = v
		end
		t.GetEnumItems = function()
			return table.clone(list)
		end
		return table.freeze(t)
	end,
})

---------------------------------------------------------------------------
-- Services that aren't instances in the place file
---------------------------------------------------------------------------
local RunService = { Heartbeat = Signal.new("Heartbeat"), Stepped = Signal.new("Stepped") }
function RunService:IsServer()
	return role == "server"
end
function RunService:IsClient()
	return role == "client"
end
function RunService:IsStudio()
	return false
end

-- The cursor and pointer-lock settings scripts can change (LocalScripts only).
local mouseSettings = { MouseIcon = "", MouseIconEnabled = true, MouseBehavior = "Default" }
-- Where the pointer is, fed by the host: screen X/Y and what's under it in the world.
local mouseState = { x = 0, y = 0, hit = v3(0, 0, 0), target = nil, origin = v3(0, 0, 0), dir = v3(0, 0, -1) }

local UIS = {
	InputBegan = Signal.new("InputBegan"),
	InputEnded = Signal.new("InputEnded"),
	InputChanged = Signal.new("InputChanged"),
	TouchEnabled = false,
	KeyboardEnabled = false,
	MouseEnabled = false,
	_down = {},
}
function UIS:IsKeyDown(key)
	return UIS._down[tostring(key)] == true
end
function UIS:IsMouseButtonPressed(button)
	return UIS._down[tostring(button)] == true
end
function UIS:GetMouseLocation()
	return v2(mouseState.x, mouseState.y)
end

local function emitMouseSettings()
	if role == "client" then
		emit({ o = "mouse", icon = mouseSettings.MouseIcon, enabled = mouseSettings.MouseIconEnabled, behavior = mouseSettings.MouseBehavior })
	end
end

local function setMouseSetting(key, value, level)
	if key == "MouseIcon" then
		value = value == nil and "" or tostring(value)
	elseif key == "MouseIconEnabled" then
		if type(value) ~= "boolean" then
			error("MouseIconEnabled must be true or false", level)
		end
	elseif key == "MouseBehavior" then
		value = tostring(value)
		if not table.find(enums.MouseBehavior, value) then
			error('MouseBehavior must be "Default", "LockCenter" or "LockCurrentPosition"', level)
		end
	else
		error(tostring(key) .. " is not a valid member of UserInputService", level)
	end
	if mouseSettings[key] ~= value then
		mouseSettings[key] = value
		emitMouseSettings()
	end
end

local UserInputService = setmetatable({}, {
	__index = function(_, key)
		if mouseSettings[key] ~= nil then
			return mouseSettings[key]
		end
		return UIS[key]
	end,
	__newindex = function(_, key, value)
		setMouseSetting(key, value, 3)
	end,
	__tostring = function()
		return "UserInputService"
	end,
})

-- Player:GetMouse(): the pointer as an object (Hit, Target, Button1Down...).
local mouseSignals = {}
for _, name in { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "WheelForward", "WheelBackward" } do
	mouseSignals[name] = Signal.new(name)
end
local Mouse = setmetatable({}, {
	__index = function(_, key)
		if key == "Hit" then
			return mouseState.hit
		elseif key == "Target" then
			local t = mouseState.target
			return t and D[t] and not D[t].destroyed and t or nil
		elseif key == "X" then
			return mouseState.x
		elseif key == "Y" then
			return mouseState.y
		elseif key == "Origin" then
			return mouseState.origin
		elseif key == "UnitRay" then
			return table.freeze({ Origin = mouseState.origin, Direction = mouseState.dir })
		elseif key == "Icon" then
			return mouseSettings.MouseIcon
		elseif mouseSignals[key] then
			return mouseSignals[key]
		end
		error(tostring(key) .. " is not a valid member of Mouse", 2)
	end,
	__newindex = function(_, key, value)
		if key ~= "Icon" then
			error(tostring(key) .. " can't be set on Mouse", 2)
		end
		setMouseSetting("MouseIcon", value, 3)
	end,
	__tostring = function()
		return "Mouse"
	end,
})
toolMouse = Mouse

-- Place translations: Strings.get("coins", 5) -> "Монеты: 5" for a Russian player.
local Strings = {}
function Strings.get(key, ...)
	local entry = stringsTable[key]
	local text = key
	if type(entry) == "table" then
		text = entry[playerLang] or entry.en or entry._default or key
		for _, v in entry do
			if text == key and type(v) == "string" then
				text = v
			end
		end
	end
	local args = table.pack(...)
	for i = 1, args.n do
		text = string.gsub(text, "{" .. (i - 1) .. "}", tostring(args[i]))
	end
	return text
end
function Strings.forPlayer(player, key, ...)
	local lang = isInstance(player) and D[player].props.Language or playerLang
	local prev = playerLang
	playerLang = lang
	local text = Strings.get(key, ...)
	playerLang = prev
	return text
end
local LocalizationService = {}
function LocalizationService:GetString(key, ...)
	return Strings.get(key, ...)
end

local easing = {
	Linear = function(t)
		return t
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
	Back = function(t)
		return t * t * (2.70158 * t - 1.70158)
	end,
	Bounce = function(t)
		t = 1 - t
		local v
		if t < 1 / 2.75 then
			v = 7.5625 * t * t
		elseif t < 2 / 2.75 then
			t -= 1.5 / 2.75
			v = 7.5625 * t * t + 0.75
		elseif t < 2.5 / 2.75 then
			t -= 2.25 / 2.75
			v = 7.5625 * t * t + 0.9375
		else
			t -= 2.625 / 2.75
			v = 7.5625 * t * t + 0.984375
		end
		return 1 - v
	end,
	Elastic = function(t)
		if t == 0 or t == 1 then
			return t
		end
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1.075) * (2 * math.pi) / 0.3)
	end,
}
local function ease(style, dir, t)
	local f = easing[style] or easing.Quad
	if dir == "In" then
		return f(t)
	elseif dir == "Out" then
		return 1 - f(1 - t)
	end
	if t < 0.5 then
		return f(t * 2) / 2
	end
	return 1 - f((1 - t) * 2) / 2
end
local function lerpValue(a, b, t)
	local ty = typeOf(a)
	if ty == "number" then
		return a + (b - a) * t
	elseif ty == "Vector3" or ty == "Vector2" or ty == "Color3" or ty == "UDim2" then
		return a:Lerp(b, t)
	end
	return t < 1 and a or b
end

local tweens = {}
local TweenService = {}
function TweenService:Create(inst, info, goals)
	if not isInstance(inst) then
		error("TweenService:Create needs an Instance", 2)
	end
	info = info or TweenInfo.new()
	local tw = { Instance = inst, TweenInfo = info, PlaybackState = "Begin", Completed = Signal.new("Completed") }
	function tw.Play(selfTw)
		selfTw._from = {}
		for k in goals do
			selfTw._from[k] = inst[k]
		end
		selfTw._t = -info.DelayTime
		selfTw._repeats = info.RepeatCount
		selfTw._back = false
		selfTw.PlaybackState = "Playing"
		tweens[selfTw] = true
	end
	function tw.Cancel(selfTw)
		tweens[selfTw] = nil
		selfTw.PlaybackState = "Cancelled"
	end
	function tw.Pause(selfTw)
		tweens[selfTw] = nil
		selfTw.PlaybackState = "Paused"
	end
	function tw._step(selfTw, dt)
		selfTw._t += dt
		if selfTw._t < 0 then
			return
		end
		local a = math.clamp(selfTw._t / math.max(info.Time, 0.001), 0, 1)
		local k = ease(info.EasingStyle, info.EasingDirection, selfTw._back and 1 - a or a)
		if not D[inst] or D[inst].destroyed then
			tweens[selfTw] = nil
			return
		end
		for key, goal in goals do
			inst[key] = lerpValue(selfTw._from[key], goal, k)
		end
		if a >= 1 then
			if info.Reverses and not selfTw._back then
				selfTw._back = true
				selfTw._t = 0
			elseif selfTw._repeats ~= 0 then
				selfTw._repeats -= 1
				selfTw._back = false
				selfTw._t = 0
			else
				tweens[selfTw] = nil
				selfTw.PlaybackState = "Completed"
				selfTw.Completed:_fire("Completed")
			end
		end
	end
	return tw
end

---------------------------------------------------------------------------
-- Class methods
---------------------------------------------------------------------------
local pendingInvokes = {} -- rid -> thread
local nextRid = 1

local function packArgs(...)
	local n = select("#", ...)
	local out = { __array = n == 0 or nil }
	for i = 1, n do
		out[i] = encodeValue((select(i, ...)))
	end
	return out
end
local function unpackArgs(list)
	local out = {}
	local n = 0
	for i, v in list or {} do
		if type(i) == "number" then
			out[i] = decodeValue(v)
			n = math.max(n, i)
		end
	end
	return table.unpack(out, 1, n)
end

local function userIdOf(player)
	if not isInstance(player) or D[player].class.name ~= "Player" then
		error("expected a Player", 3)
	end
	return D[player].props.UserId
end

Methods.RemoteEvent = {
	FireServer = function(self, ...)
		if role ~= "client" then
			error("FireServer can only be called from a LocalScript", 2)
		end
		emit({ o = "fire", id = D[self].id, args = packArgs(...) })
	end,
	FireClient = function(self, player, ...)
		if role ~= "server" then
			error("FireClient can only be called from a Script", 2)
		end
		emit({ o = "fire", id = D[self].id, to = userIdOf(player), args = packArgs(...) })
	end,
	FireAllClients = function(self, ...)
		if role ~= "server" then
			error("FireAllClients can only be called from a Script", 2)
		end
		emit({ o = "fire", id = D[self].id, to = "all", args = packArgs(...) })
	end,
}
Methods.RemoteFunction = {
	InvokeServer = function(self, ...)
		if role ~= "client" then
			error("InvokeServer can only be called from a LocalScript", 2)
		end
		local rid = nextRid
		nextRid += 1
		pendingInvokes[rid] = coroutine.running()
		emit({ o = "invoke", id = D[self].id, rid = rid, args = packArgs(...) })
		local ok, result = coroutine.yield()
		if not ok then
			error(result, 2)
		end
		return unpackArgs(result)
	end,
}
Methods.BindableEvent = {
	Fire = function(self, ...)
		fireEvent(self, "Event", ...)
	end,
}
Methods.Sound = {
	Play = function(self)
		setProp(self, "Playing", true)
		if inScope(self) then
			emit({ o = "sound", id = D[self].id })
		end
	end,
	Stop = function(self)
		setProp(self, "Playing", false)
	end,
}
Methods.Model = {
	-- Moves every part of the model so that its center lands on `pos`.
	MoveTo = function(self, pos)
		local parts = {}
		for _, v in descendants(self, {}) do
			if D[v].class.isA.BasePart or D[v].class.name == "Text3D" then
				parts[#parts + 1] = v
			end
		end
		if #parts == 0 then
			return
		end
		local sum = v3(0, 0, 0)
		for _, p in parts do
			sum += D[p].props.Position
		end
		local delta = pos - sum / #parts
		for _, p in parts do
			p.Position = D[p].props.Position + delta
		end
	end,
	GetCenter = function(self)
		local sum, n = v3(0, 0, 0), 0
		for _, v in descendants(self, {}) do
			if D[v].class.isA.BasePart then
				sum += D[v].props.Position
				n += 1
			end
		end
		return n > 0 and sum / n or sum
	end,
}

---------------------------------------------------------------------------
-- Raycasts and area queries (plain math over the parts: same answer on server and client)
---------------------------------------------------------------------------
-- A part's rotation (degrees) as a row-major 3x3 matrix, in the renderer's Y * X * Z order.
local function rotMatrix(r)
	local x, y, z = math.rad(r.X), math.rad(r.Y), math.rad(r.Z)
	local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
	local a11, a12, a13 = cy, sy * sx, sy * cx
	local a21, a22, a23 = 0, cx, -sx
	local a31, a32, a33 = -sy, cy * sx, cy * cx
	return {
		a11 * cz + a12 * sz, -a11 * sz + a12 * cz, a13,
		a21 * cz + a22 * sz, -a21 * sz + a22 * cz, a23,
		a31 * cz + a32 * sz, -a31 * sz + a32 * cz, a33,
	}
end

local RaycastParams = {}
local RPmt = { __type = "RaycastParams" }
RPmt.__index = RPmt
function RaycastParams.new()
	return setmetatable({ FilterDescendantsInstances = {}, FilterType = "Exclude", RespectCanCollide = false }, RPmt)
end
table.freeze(RaycastParams)

-- Every BasePart in the Workspace that the params let through.
local function queryParts(params)
	local out = {}
	local filter = {}
	local include = false
	if params ~= nil then
		if type(params) ~= "table" then
			error("expected RaycastParams", 3)
		end
		for _, v in params.FilterDescendantsInstances or {} do
			if isInstance(v) then
				filter[v] = true
			end
		end
		include = params.FilterType == "Include"
	end
	local respect = params and params.RespectCanCollide == true
	local function walk(inst, inFilter)
		for _, ch in D[inst].children do
			local f = inFilter or filter[ch] == true
			local cd = D[ch]
			if cd.class.isA.BasePart and (f == include) and (not respect or cd.props.CanCollide) then
				out[#out + 1] = ch
			end
			walk(ch, f)
		end
	end
	if services.Workspace then
		walk(services.Workspace, false)
	end
	return out
end

-- Where a ray (origin o, vector dir, t in 0..1) first enters a part: t and the surface normal.
local function rayPart(part, o, dir)
	local p = D[part].props
	local c, size = p.Position, p.Size
	local rx, ry, rz = o.X - c.X, o.Y - c.Y, o.Z - c.Z
	if D[part].class.name == "Part" and p.Shape == "Ball" then
		local r = math.min(size.X, size.Y, size.Z) / 2
		local a = dir.X * dir.X + dir.Y * dir.Y + dir.Z * dir.Z
		local b = 2 * (rx * dir.X + ry * dir.Y + rz * dir.Z)
		local cc = rx * rx + ry * ry + rz * rz - r * r
		local disc = b * b - 4 * a * cc
		if a == 0 or cc <= 0 or disc < 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		if t < 0 or t > 1 then
			return nil
		end
		return t, v3(rx + dir.X * t, ry + dir.Y * t, rz + dir.Z * t).Unit
	end
	-- Boxes (cylinders and wedges count as their box): slabs in the part's own axes.
	local m = rotMatrix(p.Rotation)
	local lo = { m[1] * rx + m[4] * ry + m[7] * rz, m[2] * rx + m[5] * ry + m[8] * rz, m[3] * rx + m[6] * ry + m[9] * rz }
	local ld = { m[1] * dir.X + m[4] * dir.Y + m[7] * dir.Z, m[2] * dir.X + m[5] * dir.Y + m[8] * dir.Z, m[3] * dir.X + m[6] * dir.Y + m[9] * dir.Z }
	local half = { size.X / 2, size.Y / 2, size.Z / 2 }
	local tmin, tmax, axis, sign = 0, 1, 0, 0
	for i = 1, 3 do
		if math.abs(ld[i]) < 1e-9 then
			if math.abs(lo[i]) > half[i] then
				return nil
			end
		else
			local t1 = (-half[i] - lo[i]) / ld[i]
			local t2 = (half[i] - lo[i]) / ld[i]
			local near, far = math.min(t1, t2), math.max(t1, t2)
			if near > tmin then
				tmin, axis, sign = near, i, ld[i] > 0 and -1 or 1
			end
			tmax = math.min(tmax, far)
			if tmin > tmax then
				return nil
			end
		end
	end
	if axis == 0 then
		return nil -- the ray starts inside this part
	end
	-- The local axis back to world space is column `axis` of the matrix.
	return tmin, v3(m[axis] * sign, m[3 + axis] * sign, m[6 + axis] * sign)
end

local function raycast(origin, direction, params)
	if typeOf(origin) ~= "Vector3" or typeOf(direction) ~= "Vector3" then
		error("Raycast needs an origin and a direction (Vector3)", 3)
	end
	if direction.Magnitude > 5000 then
		direction = direction.Unit * 5000
	end
	local best, bestT, bestN = nil, math.huge, nil
	for _, part in queryParts(params) do
		local t, n = rayPart(part, origin, direction)
		if t and t < bestT then
			best, bestT, bestN = part, t, n
		end
	end
	if not best then
		return nil
	end
	return table.freeze({
		Instance = best,
		Position = origin + direction * bestT,
		Normal = bestN,
		Distance = direction.Magnitude * bestT,
		Material = D[best].props.Material,
	})
end

Methods.Workspace = {
	-- The first part a ray hits: { Instance, Position, Normal, Distance, Material } or nil.
	Raycast = function(_, origin, direction, params)
		return raycast(origin, direction, params)
	end,
	-- Parts whose bounding box comes within `radius` of `position`.
	GetPartBoundsInRadius = function(_, position, radius, params)
		if typeOf(position) ~= "Vector3" then
			error("GetPartBoundsInRadius needs a Vector3 position", 2)
		end
		radius = tonumber(radius) or 0
		local out = {}
		for _, part in queryParts(params) do
			local p = D[part].props
			local m = rotMatrix(p.Rotation)
			local h = p.Size / 2
			local d2 = 0
			for i, axis in { "X", "Y", "Z" } do
				local e = math.abs(m[i * 3 - 2]) * h.X + math.abs(m[i * 3 - 1]) * h.Y + math.abs(m[i * 3]) * h.Z
				local dist = math.max(math.abs(position[axis] - p.Position[axis]) - e, 0)
				d2 += dist * dist
			end
			if d2 <= radius * radius then
				out[#out + 1] = part
			end
		end
		return out
	end,
}

---------------------------------------------------------------------------
-- Small services: Debris, HttpService (JSON), StarterGui core UI switches
---------------------------------------------------------------------------
local Debris = {}
function Debris:AddItem(inst, lifetime)
	if not isInstance(inst) then
		error("Debris:AddItem needs an Instance", 2)
	end
	task.delay(tonumber(lifetime) or 10, function()
		if D[inst] and not D[inst].destroyed then
			destroy(inst)
		end
	end)
end

local HttpService = {}
function HttpService:JSONEncode(value)
	return json.encode(value)
end
function HttpService:JSONDecode(text)
	local ok, v = pcall(json.decode, tostring(text))
	if not ok then
		error("JSONDecode: not valid JSON", 2)
	end
	return v
end
function HttpService:GenerateGUID(braces)
	local hex = "0123456789ABCDEF"
	local out = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(ch)
		local v = ch == "x" and math.random(0, 15) or math.random(8, 11)
		return string.sub(hex, v + 1, v + 1)
	end)
	return braces == false and out or "{" .. out .. "}"
end

-- Built-in parts of the game's UI a place can hide: StarterGui:SetCoreGuiEnabled("Backpack", false).
local coreGui = { Backpack = true, Health = true, Chat = true, Emotes = true }
Methods.StarterGui = {
	SetCoreGuiEnabled = function(_, kind, enabled)
		kind = tostring(kind)
		if not table.find(enums.CoreGuiType, kind) then
			error("unknown core UI " .. kind .. ' (Backpack, Health, Chat, Emotes or All)', 2)
		end
		for k in coreGui do
			if kind == "All" or k == kind then
				coreGui[k] = enabled == true
				if role == "client" then
					emit({ o = "coregui", k = k, on = coreGui[k] })
				end
			end
		end
	end,
	GetCoreGuiEnabled = function(_, kind)
		return coreGui[tostring(kind)] ~= false
	end,
}

---------------------------------------------------------------------------
-- Players and characters (the server owns health; clients own movement)
---------------------------------------------------------------------------
local playersByUser = {} -- userId -> Player
local respawnAt = {} -- Player -> sim time

local function starterValue(key)
	local sp = services.StarterPlayer
	return sp and D[sp].props[key]
end

local function spawnPosition()
	local spawns = {}
	for _, v in descendants(services.Workspace, {}) do
		if D[v].class.name == "SpawnLocation" and D[v].props.Enabled then
			spawns[#spawns + 1] = v
		end
	end
	if #spawns == 0 then
		return v3(0, 3, 0)
	end
	local s = spawns[math.random(1, #spawns)]
	local p = D[s].props
	return p.Position + v3((math.random() - 0.5) * p.Size.X * 0.6, p.Size.Y / 2 + 1.2, (math.random() - 0.5) * p.Size.Z * 0.6)
end

local function backpackOf(player)
	return player and D[player] and Methods.Instance.FindFirstChildOfClass(player, "Backpack")
end

-- Every spawn starts with a fresh Backpack: a copy of each Tool in StarterPack.
local function refillBackpack(player)
	local bp = backpackOf(player)
	if not bp then
		return
	end
	for _, ch in table.clone(D[bp].children) do
		destroy(ch)
	end
	if services.StarterPack then
		for _, ch in D[services.StarterPack].children do
			if D[ch].class.name == "Tool" then
				setParent(clone(ch), bp)
			end
		end
	end
end

local function loadCharacter(player)
	local pd = D[player]
	local old = pd.props.Character
	if old and D[old] then
		destroy(old)
	end
	refillBackpack(player)
	local model = create("Model")
	D[model].name = pd.name
	local root = create("Part")
	D[root].name = "HumanoidRootPart"
	local rp = D[root].props
	rp.Size = v3(1.2, 1.8, 0.8)
	rp.Transparency = 1
	rp.CanCollide = false
	rp.Anchored = true
	rp.CastShadow = false
	local pos = spawnPosition()
	rp.Position = pos
	D[root].parent = model
	table.insert(D[model].children, root)
	local hum = create("Humanoid")
	local hp = D[hum].props
	for _, k in { "WalkSpeed", "SprintSpeed", "JumpPower", "CanJump", "AutoHeal", "HealthRegen", "EmotesEnabled", "MaxHealth" } do
		local v = starterValue(k)
		if v ~= nil then
			hp[k] = v
		end
	end
	hp.Health = hp.MaxHealth
	D[hum].parent = model
	table.insert(D[model].children, hum)
	setParent(model, services.Workspace)
	pd.props.Character = model
	if inScope(player) then
		emitSet(player, "Character", model)
	end
	firePropChanged(player, "Character")
	emit({ o = "spawn", to = pd.props.UserId, pos = encodeValue(pos) })
	fireEvent(player, "CharacterAdded", model)
end

-- Server: puts `tool` in the character's hand; whatever it held goes back to the Backpack.
local function equipTool(hum, tool)
	local model = D[hum].parent
	if not model or D[hum].props.Health <= 0 then
		return
	end
	local player = Methods.Players.GetPlayerFromCharacter(nil, model)
	local bp = backpackOf(player)
	for _, ch in table.clone(D[model].children) do
		if ch ~= tool and D[ch].class.name == "Tool" then
			setParent(ch, bp)
		end
	end
	if tool and D[tool].parent ~= model then
		setParent(tool, model)
	end
end

local function expectTool(tool)
	if not isInstance(tool) or D[tool].class.name ~= "Tool" then
		error("expected a Tool", 3)
	end
end

Methods.Humanoid = {
	TakeDamage = function(self, amount)
		local p = D[self].props
		if p.Health > 0 then
			self.Health = math.max(0, p.Health - (tonumber(amount) or 0))
		end
	end,
	EquipTool = function(self, tool)
		expectTool(tool)
		if role == "client" then
			emit({ o = "equip", id = D[tool].id })
			return
		end
		equipTool(self, tool)
	end,
	UnequipTools = function(self)
		if role == "client" then
			emit({ o = "equip" })
			return
		end
		equipTool(self, nil)
	end,
}

Methods.Tool = {
	-- Fires Activated as if the player clicked (on this side only).
	Activate = function(self)
		if D[self].props.Enabled then
			fireEvent(self, "Activated")
		end
	end,
	Deactivate = function(self)
		fireEvent(self, "Deactivated")
	end,
}

Methods.Player = {
	-- LocalScripts: the pointer (Hit, Target, X, Y, Icon, Button1Down...).
	GetMouse = function(self)
		if role ~= "client" or D[self].props.UserId ~= localUserId then
			error("GetMouse only works on the LocalPlayer in a LocalScript", 2)
		end
		return Mouse
	end,
	Kick = function(self, message)
		if role ~= "server" then
			error("Kick can only be called from a Script", 2)
		end
		emit({ o = "kick", to = D[self].props.UserId, msg = tostring(message or "") })
	end,
	LoadCharacter = function(self)
		if role ~= "server" then
			error("LoadCharacter can only be called from a Script", 2)
		end
		respawnAt[self] = nil
		loadCharacter(self)
	end,
	-- Moves the player's character (server: tells their app to teleport).
	Teleport = function(self, pos)
		if typeOf(pos) ~= "Vector3" then
			error("Teleport needs a Vector3", 2)
		end
		-- Only the server moves characters: a client-side teleport would look like cheating.
		if role ~= "server" then
			error("Teleport can only be called from a Script (use a RemoteEvent to ask the server)", 2)
		end
		emit({ o = "spawn", to = D[self].props.UserId, pos = encodeValue(pos) })
	end,
}

Methods.Players = {
	GetPlayers = function(self)
		local out = {}
		for _, ch in D[self].children do
			if D[ch].class.name == "Player" then
				out[#out + 1] = ch
			end
		end
		return out
	end,
	GetPlayerByUserId = function(_, id)
		return playersByUser[tonumber(id)]
	end,
	GetPlayerFromCharacter = function(_, model)
		for _, p in playersByUser do
			if D[p].props.Character == model then
				return p
			end
		end
		return nil
	end,
}

-- Health rules run where health lives (the server): dying, respawning, healing.
local humanoidHealthChanged
propHooks.Humanoid = {
	Health = function(hum)
		humanoidHealthChanged(hum)
	end,
}
function humanoidHealthChanged(hum)
	local d = D[hum]
	local p = d.props
	fireEvent(hum, "HealthChanged", p.Health)
	if p.Health <= 0 and not d.dead then
		d.dead = true
		fireEvent(hum, "Died")
		if role == "server" then
			local model = d.parent
			local player = model and Methods.Players.GetPlayerFromCharacter(nil, model)
			if player then
				respawnAt[player] = simTime + (starterValue("RespawnTime") or 3)
			end
		end
	end
end

local function stepHumanoids(dt)
	for player, at in respawnAt do
		if not D[player] or D[player].destroyed then
			respawnAt[player] = nil
		elseif simTime >= at then
			respawnAt[player] = nil
			loadCharacter(player)
		end
	end
	for _, player in playersByUser do
		local model = D[player].props.Character
		local hum = model and D[model] and Methods.Instance.FindFirstChildOfClass(model, "Humanoid")
		if hum then
			local p = D[hum].props
			if p.AutoHeal and p.Health > 0 and p.Health < p.MaxHealth and p.HealthRegen > 0 then
				hum.Health = math.min(p.MaxHealth, p.Health + p.HealthRegen * dt)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Scripts
---------------------------------------------------------------------------
local sharedEnv -- globals every script sees (read-only)
local moduleCache = {} -- ModuleScript -> { done, value } or { loading = true }

local function scriptPrint(level, ...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	local src = currentScript and D[currentScript] and getFullName(currentScript) or nil
	emit({ o = "print", level = level, msg = table.concat(parts, " "), src = src })
end

function report(msg, scriptInst)
	local src = scriptInst and D[scriptInst] and getFullName(scriptInst) or nil
	emit({ o = "print", level = "error", msg = tostring(msg), src = src })
end

local function loadChunk(scriptInst)
	local d = D[scriptInst]
	local source = d.props.Source or ""
	local fn, err = compile(source, "=" .. getFullName(scriptInst))
	if not fn then
		report(err, scriptInst)
		return nil
	end
	local env = setmetatable({ script = scriptInst }, { __index = sharedEnv })
	setfenv(fn, env)
	return fn
end

local function requireModule(mod)
	if not isInstance(mod) or D[mod].class.name ~= "ModuleScript" then
		error("require needs a ModuleScript", 2)
	end
	local cached = moduleCache[mod]
	if cached then
		if cached.loading then
			error("require loop: " .. getFullName(mod) .. " requires itself", 2)
		end
		return cached.value
	end
	moduleCache[mod] = { loading = true }
	local fn = loadChunk(mod)
	if not fn then
		moduleCache[mod] = nil
		error("module " .. getFullName(mod) .. " failed to compile", 2)
	end
	local prev = currentScript
	currentScript = mod
	local ok, value = pcall(fn)
	currentScript = prev
	if not ok then
		moduleCache[mod] = nil
		error(value, 2)
	end
	moduleCache[mod] = { value = value }
	return value
end

-- Is this script allowed to run where it is right now?
local function runnable(inst)
	local d = D[inst]
	if not d.props.Enabled then
		return false
	end
	local cls = d.class.name
	if cls == "Script" and role == "server" then
		-- The Players service holds Backpacks, so Scripts in a player's Tools run too.
		for _, svc in { services.Workspace, services.ServerScriptService, services.Players } do
			if svc and Methods.Instance.IsDescendantOf(inst, svc) then
				return true
			end
		end
		return false
	elseif cls == "LocalScript" and role == "client" then
		local me = localUserId and playersByUser[localUserId]
		if not me then
			return false
		end
		-- Under the LocalPlayer (PlayerGui, PlayerScripts, Backpack) or in their character.
		local char = D[me].props.Character
		return Methods.Instance.IsDescendantOf(inst, me) or (char ~= nil and D[char] ~= nil and Methods.Instance.IsDescendantOf(inst, char))
	end
	return false
end

local function runScript(inst)
	local d = D[inst]
	if d.ran or not runnable(inst) then
		return
	end
	d.ran = true
	local fn = loadChunk(inst)
	if not fn then
		return
	end
	local co = coroutine.create(fn)
	threadScript[co] = inst
	resume(co)
end

function startScriptsIn(root)
	local list = { root }
	descendants(root, list)
	for _, v in list do
		local cls = D[v].class.name
		if cls == "Script" or cls == "LocalScript" then
			runScript(v)
		end
	end
end

propHooks.Script = {
	Enabled = function(inst)
		if started and D[inst].props.Enabled then
			runScript(inst)
		end
	end,
}
propHooks.LocalScript = propHooks.Script

---------------------------------------------------------------------------
-- Building the tree from a place (.melt) and from the network
---------------------------------------------------------------------------
-- Place instance JSON: { c = class, n = name, p = { props }, k = { children } }
local function buildFromPlace(node, parent)
	if type(node) ~= "table" or not classes[node.c] then
		return nil
	end
	local inst
	if node.c == "DataModel" then
		inst = DataModel
	elseif classes[node.c].raw.service and parent == DataModel then
		inst = services[node.c] or create(node.c)
		services[node.c] = inst
	else
		inst = create(node.c)
	end
	local d = D[inst]
	d.name = node.n or node.c
	for k, v in node.p or {} do
		local p = d.class.props[k]
		if p then
			local ok, val = pcall(coerce, d.class, k, p, decodeValue(v))
			if ok then
				d.props[k] = val
			end
		end
	end
	if parent and inst ~= DataModel and d.parent ~= parent then
		d.parent = parent
		table.insert(D[parent].children, inst)
	end
	for _, ch in node.k or {} do
		buildFromPlace(ch, inst)
	end
	return inst
end

local function ensureServices()
	for _, name in schema.services do
		if not services[name] then
			local s = create(name)
			D[s].name = name
			D[s].parent = DataModel
			table.insert(D[DataModel].children, s)
			services[name] = s
		end
	end
	if not services.Players then
		local s = create("Players")
		D[s].name = "Players"
		D[s].parent = DataModel
		table.insert(D[DataModel].children, s)
		services.Players = s
	end
	local sp = services.StarterPlayer
	if not Methods.Instance.FindFirstChildOfClass(sp, "StarterPlayerScripts") then
		local s = create("StarterPlayerScripts")
		D[s].name = "StarterPlayerScripts"
		D[s].parent = sp
		table.insert(D[sp].children, s)
	end
end

-- Snapshot of everything a joining player should see, as "new" operations.
local function snapshotOps()
	local saved = ops
	ops = {}
	for _, ch in D[DataModel].children do
		if inScope(ch) then
			emitNew(ch)
		end
	end
	local out = ops
	ops = saved
	return out
end

---------------------------------------------------------------------------
-- DataModel (game) and the globals scripts see
---------------------------------------------------------------------------
local specialServices = {
	RunService = RunService,
	TweenService = TweenService,
	UserInputService = UserInputService,
	LocalizationService = LocalizationService,
	Debris = Debris,
	HttpService = HttpService,
}
Methods.DataModel = {
	GetService = function(_, name)
		if specialServices[name] then
			return specialServices[name]
		end
		local s = services[name]
		if not s then
			error("no service named " .. tostring(name), 2)
		end
		return s
	end,
}
Methods.DataModel.FindService = Methods.DataModel.GetService

local G = _G
local function buildEnv()
	local safeOs = table.freeze({ clock = os.clock, time = os.time, date = os.date, difftime = os.difftime })
	local safeDebug = table.freeze({ traceback = debug.traceback, info = debug.info })
	local env = {
		game = DataModel,
		Instance = table.freeze({ new = Instance.new }),
		Vector3 = table.freeze(Vector3),
		Vector2 = table.freeze(Vector2),
		Color3 = table.freeze(Color3),
		UDim = table.freeze(UDim),
		UDim2 = table.freeze(UDim2),
		TweenInfo = table.freeze(TweenInfo),
		RaycastParams = RaycastParams,
		OverlapParams = RaycastParams,
		Enum = Enum,
		task = table.freeze(task),
		wait = task.wait,
		spawn = task.spawn,
		delay = task.delay,
		print = function(...)
			scriptPrint("info", ...)
		end,
		warn = function(...)
			scriptPrint("warn", ...)
		end,
		require = requireModule,
		typeof = function(v)
			if isInstance(v) then
				return "Instance"
			end
			return typeOf(v)
		end,
		tick = function()
			return os.time() + (clock() % 1)
		end,
		time = function()
			return simTime
		end,
		Strings = table.freeze(Strings),
		os = safeOs,
		debug = safeDebug,
	}
	-- Plain Luau libraries and functions; the host hooks (__init...) and fenv stay hidden.
	for _, name in {
		"math", "string", "table", "coroutine", "utf8", "bit32", "buffer", "vector",
		"pairs", "ipairs", "next", "select", "type", "tostring", "tonumber", "pcall", "xpcall", "error",
		"assert", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen", "unpack", "newproxy", "gcinfo",
	} do
		if env[name] == nil and G[name] ~= nil then
			env[name] = G[name]
		end
	end
	env._G = env
	-- On a client the Workspace arrives from the server after this runs, so look it up late.
	setmetatable(env, {
		__index = function(_, key)
			if key == "workspace" or key == "Workspace" then
				return services.Workspace
			end
			return nil
		end,
	})
	return table.freeze(env)
end

---------------------------------------------------------------------------
-- Client setup: PlayerGui and PlayerScripts come from StarterGui / StarterPlayerScripts
---------------------------------------------------------------------------
local localReady = false
local function setupLocalPlayer()
	if localReady or role ~= "client" or not started then
		return
	end
	local me = localUserId and playersByUser[localUserId]
	if not me then
		return
	end
	localReady = true
	local pl = services.Players
	D[pl].extra = D[pl].extra or {}
	D[pl].extra.LocalPlayer = me
	-- workspace.CurrentCamera exists only on this device.
	local ws = services.Workspace
	if ws then
		local cam = create("Camera")
		D[cam].name = "Camera"
		setParent(cam, ws)
		D[ws].extra = D[ws].extra or {}
		D[ws].extra.CurrentCamera = cam
	end
	local gui = create("PlayerGui")
	D[gui].name = "PlayerGui"
	setParent(gui, me)
	local scripts = create("PlayerScripts")
	D[scripts].name = "PlayerScripts"
	setParent(scripts, me)
	if services.StarterGui then
		for _, ch in D[services.StarterGui].children do
			setParent(clone(ch), gui)
		end
	end
	local sps = services.StarterPlayer and Methods.Instance.FindFirstChildOfClass(services.StarterPlayer, "StarterPlayerScripts")
	if sps then
		for _, ch in D[sps].children do
			setParent(clone(ch), scripts)
		end
	end
end

---------------------------------------------------------------------------
-- Host API
---------------------------------------------------------------------------
local handlers = {}

local function characterRoot(player)
	local model = player and D[player] and D[player].props.Character
	return model and D[model] and findChild(model, "HumanoidRootPart")
end
local function humanoidOf(player)
	local model = player and D[player] and D[player].props.Character
	return model and D[model] and Methods.Instance.FindFirstChildOfClass(model, "Humanoid")
end

-- server: a player joined / left
function handlers.player_add(e)
	local p = create("Player")
	local d = D[p]
	d.name = tostring(e.name)
	d.props.DisplayName = tostring(e.display or e.name)
	d.props.UserId = tonumber(e.userId) or 0
	d.props.Language = tostring(e.lang or "en")
	d.props.CameraMode = starterValue("CameraMode") or "Classic"
	d.props.CameraMinZoom = starterValue("CameraMinZoom") or 0.5
	d.props.CameraMaxZoom = starterValue("CameraMaxZoom") or 14
	playersByUser[d.props.UserId] = p
	local bp = create("Backpack")
	D[bp].name = "Backpack"
	setParent(bp, p)
	setParent(p, services.Players)
	fireEvent(services.Players, "PlayerAdded", p)
	loadCharacter(p)
end
function handlers.player_remove(e)
	local p = playersByUser[tonumber(e.userId)]
	if not p then
		return
	end
	fireEvent(services.Players, "PlayerRemoving", p)
	playersByUser[tonumber(e.userId)] = nil
	respawnAt[p] = nil
	local model = D[p].props.Character
	if model and D[model] then
		destroy(model)
	end
	destroy(p)
end
-- where a player's character is (sent by their app; kept off the wire)
function handlers.pos(e)
	local player = role == "server" and playersByUser[tonumber(e.userId)] or (localUserId and playersByUser[localUserId])
	local root = characterRoot(player)
	if root then
		setProp(root, "Position", decodeValue(e.p), true)
	end
end
function handlers.died(e)
	local hum = humanoidOf(playersByUser[tonumber(e.userId)])
	if hum and D[hum].props.Health > 0 then
		hum.Health = 0
	end
end
function handlers.fire(e)
	local remote = byId[e.id]
	if not remote or D[remote].class.name ~= "RemoteEvent" then
		return
	end
	if role == "server" then
		local player = playersByUser[tonumber(e.userId)]
		if player then
			fireEvent(remote, "OnServerEvent", player, unpackArgs(e.args))
		end
	else
		fireEvent(remote, "OnClientEvent", unpackArgs(e.args))
	end
end
function handlers.invoke(e)
	local remote = byId[e.id]
	local player = playersByUser[tonumber(e.userId)]
	if not remote or not player then
		return
	end
	local rid = e.rid
	task.spawn(function()
		local cb = D[remote].extra and D[remote].extra.OnServerInvoke
		local result
		if type(cb) ~= "function" then
			result = { false, "OnServerInvoke is not set on " .. getFullName(remote) }
		else
			result = table.pack(pcall(cb, player, unpackArgs(e.args)))
		end
		local ok = result[1]
		local values = ok and packArgs(table.unpack(result, 2, result.n)) or tostring(result[2])
		emit({ o = "ret", to = D[player].props.UserId, rid = rid, ok = ok, values = values })
	end)
end
function handlers.ret(e)
	local co = pendingInvokes[e.rid]
	pendingInvokes[e.rid] = nil
	if co and coroutine.status(co) == "suspended" then
		resume(co, e.ok, e.values)
	end
end
function handlers.touch(e)
	local part = byId[e.id]
	local player = role == "server" and playersByUser[tonumber(e.userId)] or (localUserId and playersByUser[localUserId])
	local root = characterRoot(player)
	if part and root and D[part].props.CanTouch then
		fireEvent(part, e.ended and "TouchEnded" or "Touched", root)
		-- Walking into a Tool lying in the world picks it up.
		local tool = D[part] and D[part].parent
		if role == "server" and not e.ended and D[part].name == "Handle" and tool and D[tool].class.name == "Tool" then
			local hum = humanoidOf(player)
			local ws = services.Workspace
			if hum and D[hum].props.Health > 0 and not isCharacter(D[tool].parent) and Methods.Instance.IsDescendantOf(tool, ws)
				and simTime - (D[tool].droppedAt or -10) > 1.5 then
				setParent(tool, backpackOf(player))
				if not Methods.Instance.FindFirstChildOfClass(D[hum].parent, "Tool") then
					equipTool(hum, tool)
				end
			end
		end
	end
end

-- The player picked a tool in their hotbar, clicked with it, or dropped it.
function handlers.tool(e)
	local player = role == "server" and playersByUser[tonumber(e.userId)] or (localUserId and playersByUser[localUserId])
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	local model = D[hum].parent
	local tool = e.id and byId[e.id]
	if tool and D[tool].class.name ~= "Tool" then
		return
	end
	if e.ev == "activate" or e.ev == "deactivate" then
		if tool and D[tool].parent == model and D[tool].props.Enabled and D[hum].props.Health > 0 then
			fireEvent(tool, e.ev == "activate" and "Activated" or "Deactivated")
		end
		return
	end
	if role ~= "server" then
		return
	end
	if e.ev == "equip" and tool and D[tool].parent == backpackOf(player) then
		equipTool(hum, tool)
	elseif e.ev == "unequip" then
		equipTool(hum, nil)
	elseif e.ev == "drop" and tool and D[tool].parent == model and D[tool].props.CanBeDropped then
		-- Lands in front of the character (the app says where "in front" is).
		local root = characterRoot(player)
		local at = decodeValue(e.p)
		if typeOf(at) ~= "Vector3" or (root and (at - D[root].props.Position).Magnitude > 8) then
			at = root and D[root].props.Position or v3(0, 5, 0)
		end
		local handle = findChild(tool, "Handle")
		local delta = handle and at - D[handle].props.Position or v3(0, 0, 0)
		for _, v in descendants(tool, {}) do
			if D[v].class.isA.BasePart then
				v.Position = D[v].props.Position + delta
			end
		end
		D[tool].droppedAt = simTime
		setParent(tool, services.Workspace)
	end
end

-- client: where the pointer is and what's under it (sent by the app while it moves)
function handlers.mouse(e)
	local x, y = tonumber(e.x) or 0, tonumber(e.y) or 0
	local moved = x ~= mouseState.x or y ~= mouseState.y
	mouseState.x, mouseState.y = x, y
	mouseState.hit = decodeValue(e.hit) or mouseState.hit
	mouseState.origin = decodeValue(e.origin) or mouseState.origin
	mouseState.dir = decodeValue(e.dir) or mouseState.dir
	mouseState.target = e.target and byId[e.target] or nil
	if moved then
		mouseSignals.Move:_fire()
		UIS.InputChanged:_fire(table.freeze({ KeyCode = "Unknown", UserInputType = "MouseMovement", Position = v2(x, y) }), false)
	end
end

-- client: where the game's camera is (Camera.Position, Focus, LookVector)
function handlers.camera(e)
	local ws = services.Workspace
	local cam = ws and D[ws].extra and D[ws].extra.CurrentCamera
	if not cam or not D[cam] or D[cam].destroyed then
		return
	end
	local pos, focus, look = decodeValue(e.p), decodeValue(e.f), decodeValue(e.look)
	if D[cam].props.CameraType ~= "Scriptable" and isV3(pos) and isV3(focus) then
		setProp(cam, "Position", pos, true)
		setProp(cam, "Focus", focus, true)
	end
	if isV3(look) then
		setProp(cam, "LookVector", look, true)
	end
end
function handlers.click(e)
	local det = byId[e.id]
	local player = playersByUser[tonumber(e.userId)]
	if det and player and D[det].class.name == "ClickDetector" then
		fireEvent(det, "MouseClick", player)
	end
end
-- client: buttons, text boxes and hover from the rendered UI
function handlers.gui(e)
	local inst = byId[e.id]
	if not inst then
		return
	end
	if e.ev == "text" then
		setProp(inst, "Text", tostring(e.value or ""), true)
	elseif e.ev == "activated" then
		fireEvent(inst, "Activated")
		fireEvent(inst, "MouseButton1Click")
	elseif e.ev == "focus_lost" then
		fireEvent(inst, "FocusLost", e.value == true)
	elseif e.ev == "focused" then
		fireEvent(inst, "Focused")
	elseif e.ev == "enter" then
		fireEvent(inst, "MouseEnter")
	elseif e.ev == "leave" then
		fireEvent(inst, "MouseLeave")
	end
end
function handlers.input(e)
	local kind = tostring(e.kind or "Keyboard")
	local key = kind == "Keyboard" and tostring(e.key) or "Unknown"
	local pos = v2(tonumber(e.x) or mouseState.x, tonumber(e.y) or mouseState.y)
	local input = table.freeze({ KeyCode = key, UserInputType = kind, Position = pos })
	if kind == "MouseWheel" then
		UIS.InputChanged:_fire(input, e.ui == true)
		mouseSignals[e.down and "WheelForward" or "WheelBackward"]:_fire()
		return
	end
	UIS._down[kind == "Keyboard" and key or kind] = e.down == true
	if e.down then
		UIS.InputBegan:_fire(input, e.ui == true)
	else
		UIS.InputEnded:_fire(input, e.ui == true)
	end
	if e.ui ~= true then
		if kind == "MouseButton1" or kind == "Touch" then
			mouseSignals[e.down and "Button1Down" or "Button1Up"]:_fire()
		elseif kind == "MouseButton2" then
			mouseSignals[e.down and "Button2Down" or "Button2Up"]:_fire()
		end
	end
end
-- client: replication from the server (same shape as the server's operations)
function handlers.new(e)
	if byId[e.id] then
		return
	end
	local info = classes[e.c]
	if not info then
		return
	end
	local inst = create(e.c, e.id)
	local d = D[inst]
	d.name = e.n or e.c
	for k, v in e.p or {} do
		if info.props[k] then
			d.props[k] = decodeValue(v)
		end
	end
	local parent = e.parent and byId[e.parent]
	if info.raw.service and parent == DataModel then
		services[e.c] = inst
	end
	if e.c == "Player" then
		playersByUser[d.props.UserId] = inst
	end
	if parent then
		setParent(inst, parent)
	end
	if e.c == "Player" and d.props.UserId == localUserId then
		setupLocalPlayer()
	end
end
function handlers.set(e)
	local inst = byId[e.id]
	if not inst then
		return
	end
	if e.k == "Name" then
		inst.Name = e.v
	elseif D[inst].class.props[e.k] then
		setProp(inst, e.k, decodeValue(e.v))
	end
end
function handlers.del(e)
	local inst = byId[e.id]
	if inst then
		if D[inst].class.name == "Player" then
			playersByUser[D[inst].props.UserId] = nil
		end
		destroy(inst)
	end
end
function handlers.parent(e)
	local inst, parent = byId[e.id], byId[e.parent]
	if inst and parent then
		setParent(inst, parent)
	end
end

local function hostCall(fn)
	return function(arg)
		fn(arg ~= "" and json.decode(arg) or nil)
		runDeferred()
		return flush()
	end
end

G.__init = hostCall(function(cfg)
	role = cfg.role == "client" and "client" or "server"
	idPrefix = role == "client" and "c" or ""
	buildClasses(cfg.schema)
	localUserId = tonumber(cfg.userId)
	playerLang = tostring(cfg.lang or "en")
	stringsTable = cfg.strings or {}
	local device = cfg.device or {}
	UIS.TouchEnabled = device.touch == true
	UIS.KeyboardEnabled = device.keyboard == true
	UIS.MouseEnabled = device.mouse == true
	math.randomseed(tonumber(cfg.seed) or 1)
	DataModel = create("DataModel", "0")
	D[DataModel].name = "Game"
	if role == "server" then
		if cfg.place and cfg.place.tree then
			buildFromPlace(cfg.place.tree, nil)
		end
		ensureServices()
	end
	sharedEnv = buildEnv()
	-- Nothing is sent for the initial tree: joining players get a snapshot instead.
	ops = {}
end)

G.__start = hostCall(function()
	started = true
	if role == "server" then
		startScriptsIn(services.Workspace)
		startScriptsIn(services.ServerScriptService)
	else
		setupLocalPlayer()
	end
end)

G.__dispatch = hostCall(function(events)
	for _, e in events or {} do
		local h = handlers[e.e or e.o]
		if h then
			local ok, err = pcall(h, e)
			if not ok then
				report("runtime: " .. tostring(err))
			end
		end
	end
end)

G.__step = hostCall(function(t)
	local dt = math.clamp(tonumber(t and t.dt) or 0, 0, 1)
	simTime += dt
	RunService.Stepped:_fire(simTime, dt)
	runWaiting()
	for tw in table.clone(tweens) do
		tw:_step(dt)
	end
	if role == "server" then
		stepHumanoids(dt)
	end
	RunService.Heartbeat:_fire(dt)
end)

-- Studio: compile a script without running it; returns "" or the error message.
G.__check = function(source)
	local fn, err = compile(source, "=script")
	return fn and "" or tostring(err)
end

G.__snapshot = function()
	return json.encode(snapshotOps())
end

-- Movement limits per player for the server's anti-cheat: how fast and how high
-- each character may legitimately go right now.
G.__limits = function()
	local out = {}
	local ws = services.Workspace and D[services.Workspace].props or {}
	for uid, player in playersByUser do
		local hum = humanoidOf(player)
		local hp = hum and D[hum] and D[hum].props
		out[tostring(uid)] = {
			walk = hp and hp.WalkSpeed or 5,
			sprint = hp and hp.SprintSpeed or 7,
			jump = hp and (hp.CanJump and hp.JumpPower or 0) or 8.2,
			gravity = ws.Gravity or 22,
			check = starterValue("AntiCheat") ~= false,
		}
	end
	return json.encode(out)
end
