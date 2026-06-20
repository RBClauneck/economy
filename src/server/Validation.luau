--!strict
-- Pure argument validation for economy mutations. As a core library this
-- module never sees client input directly, but other server modules
-- (Market, Trading, ...) call into the economy API with arbitrary values.
-- Every amount is screened here before any balance is touched, so a bad
-- argument from one system cannot cascade into corrupted persistence.
--
-- Lua has no switch/case, and these are guard clauses on different conditions
-- (not a branch on one value), so instead of an if/elseif ladder the checks
-- are expressed as an ordered, data-driven list. They run in order and stop
-- at the first failure, which keeps later numeric tests from ever seeing a
-- non-number.

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local Validation = {}

type AmountCheck = {
	test: (amount: any) -> boolean,
	reason: string,
}

local AMOUNT_CHECKS: { AmountCheck } = {
	{ test = function(a) return type(a) == "number" end, reason = "amount must be a number" },
	{ test = function(a) return a == a end, reason = "amount is NaN" },
	{ test = function(a) return a ~= math.huge and a ~= -math.huge end, reason = "amount is infinite" },
	{ test = function(a) return a >= 0 end, reason = "amount must be non-negative" },
	{ test = function(a) return math.floor(a) == a end, reason = "amount must be an integer" },
	{ test = function(a) return a <= Constants.MAX_SAFE_AMOUNT end, reason = "amount exceeds maximum safe value" },
}

-- Validates an amount intended to be added to or removed from a balance.
-- Returns ok=false with a reason rather than raising, so callers can react.
function Validation.checkAmount(amount: number): (boolean, string?)
	for _, check in AMOUNT_CHECKS do
		if not check.test(amount) then
			return false, check.reason
		end
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
