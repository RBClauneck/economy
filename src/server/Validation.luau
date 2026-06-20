--!strict
-- Pure argument validation for economy mutations. As a core library this
-- module never sees client input directly, but other server modules
-- (Market, Trading, ...) call into the economy API with arbitrary values.
-- Every amount is screened here before any balance is touched, so a bad
-- argument from one system cannot cascade into corrupted persistence.

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local Validation = {}

-- Validates an amount intended to be added to or removed from a balance.
-- Returns ok=false with a reason rather than raising, so callers can react.
function Validation.checkAmount(amount: number): (boolean, string?)
	if type(amount) ~= "number" then
		return false, "amount must be a number"
	end
	if amount ~= amount then
		return false, "amount is NaN"
	end
	if amount == math.huge or amount == -math.huge then
		return false, "amount is infinite"
	end
	if amount < 0 then
		return false, "amount must be non-negative"
	end
	if math.floor(amount) ~= amount then
		return false, "amount must be an integer"
	end
	if amount > Constants.MAX_SAFE_AMOUNT then
		return false, "amount exceeds maximum safe value"
	end
	return true, nil
end

-- Validates the resulting balance after a mutation against the currency's
-- ceiling and the global floor. Prevents both overflow and negative debt.
function Validation.checkResult(result: number, max: number): (boolean, string?)
	if result < Constants.MIN_BALANCE then
		return false, "insufficient funds"
	end
	if result > max then
		return false, "balance exceeds currency maximum"
	end
	return true, nil
end

return Validation
