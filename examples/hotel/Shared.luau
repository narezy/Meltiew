-- ReplicatedStorage.Shared: what the lobby and the hotel agree on.
local Shared = {}

Shared.LAST_DOOR = 100
Shared.MAX_PARTY = 6

-- Door numbers as they're painted on the plates: 0007, 0042, 0100.
function Shared.door(n)
	return string.format("%04d", n)
end

-- Saved per player (DataStore "Hotel", the same in the lobby and the hotel):
-- { coins = total coins, best = the furthest door reached, escapes = times out }
function Shared.key(player)
	return "u" .. player.UserId
end

function Shared.blank()
	return { coins = 0, best = 0, escapes = 0 }
end

return Shared
