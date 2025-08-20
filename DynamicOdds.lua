local DECIMAL_POINTS = 3 --|| 0.123%, 1.234%, 12.345% by default
local COMMAS_DECIMAL_POINTS = 0 --|| 1/1,234 by default (1 would display 1/1,234.5)
local SUFFIX_DECIMAL_POINTS = 1 --|| 1/1.2K, 1/12.3M, 1/123.4B, etc. by default

local MAX_COMMAS = 5 --|| Display commas form (1/-,--- instead of 1/-.-K) up to 1/100,000 (1/1e5) by default
local PERCENT_THRESHOLD = 0.0001 --|| 0.01% or 1/10,000 by default

local SuffixList = {
	Beginning = {"K","M","B"},
	First = {"", "U","D","T","Qa","Qt","Sx","Sp","Oc","No"},
	Second = {"", "De","Vg","Tg","Qd","Qi","Se","St","Og","Ng"},
	Third = {"", "Ce"},
}

local module = {}

local Odds = {}
Odds.__index = Odds

--------------------------------------||
--| 
--|			CUSTOM ENUMS
--| 
--------------------------------------||

module.Enum = {
	StaticGroup = {
		Dynamic = 0,
		Simple = 1,
		InverseSimple = 2
	}
}

local enumFunctions = {
	StaticGroup = {
		[0] = function(oddsList: {number}) : {number}
			return nil
		end,
		[1] = function(oddsList: {number}) : {number}
			local staticGroup = {}
			for i = 1, #oddsList do
				table.insert(staticGroup, i)
			end
			return staticGroup
		end,
		[2] = function(oddsList: {number}) : {number}
			local staticGroup = {}
			for i = #oddsList, 1, -1 do
				table.insert(staticGroup, i)
			end
			return staticGroup
		end,
	}
}

--------------------------------------||
--| 
--|			ROUNDING FUNCTIONS
--| 
--------------------------------------||

local decimal = {}

local function decimalFloorTemplate(value: number, decimal_numbers: number, func: (value: number, points: number) -> number) : number
	return value < 2^53-1 and func(value, decimal_numbers) or value
end

decimal.floor = function(value: number, decimal: number) : number 
	return decimalFloorTemplate(value, decimal, function(a, b) return math.floor(a * 10^b) / 10^b end) 
end

decimal.round = function(value: number, decimal: number) : number
	return decimalFloorTemplate(value, decimal, function(a, b) return math.round(a * 10^b) / 10^b end) 
end

--------------------------------------||
--| 
--|			FORMATTING FUNCTIONS
--| 
--------------------------------------||

local function numberFormat(formatted: string) : string
	local numberOfSubs
	repeat formatted, numberOfSubs = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2') until numberOfSubs == 0
	return formatted
end

local function commas(value: number) : string
	if value < 1e3 then 
		return tostring(decimal.round(value,DECIMAL_POINTS))
	elseif value < 1e13 then
		return numberFormat(decimal.floor(value,COMMAS_DECIMAL_POINTS))
	elseif value < 1e28 then
		return numberFormat(value // 1e12) .. "," .. numberFormat(string.format("%012i",value % 1e12))
	else
		return "9"..string.rep(",999",9).."+"
	end
end

local function short(value: number) : string
	local SNumber0 = math.log10(value) // 1
	local SNumber1 = value / 10^SNumber0

	if SNumber0 == math.huge then return SNumber1 < 0 and "-Infinity" or "Infinity"
	elseif SNumber0 < 3 then return decimal.floor(value,COMMAS_DECIMAL_POINTS) end

	local leftover, SNumber = SNumber0 % 3, SNumber0 // 3 - 1

	local function getText(text)
		return math.floor(SNumber1 * 10^leftover * 10^SUFFIX_DECIMAL_POINTS + 1e-7)/10^SUFFIX_DECIMAL_POINTS .. text
	end
	local function suffixNonMult(n)
		return SuffixList.First[n%10//1 + 1]..SuffixList.Second[(n%100)//10 + 1]..SuffixList.Third[n//100 + 1]
	end

	if SNumber0 < MAX_COMMAS then return commas(value)
	elseif SNumber <= 2 then return getText(SNumber <= -1 and '' or SuffixList.Beginning[SNumber+1]) end
	return getText(suffixNonMult(SNumber))
end

--------------------------------------||
--| 
--|		ODDS CALCULATION FUNCTIONS
--| 
--------------------------------------||

local function oddsInfluence(oddsGrouped: {}, chanceIndex: number, luck: number): number
	local result = 0

	for n = 1, #oddsGrouped - chanceIndex do
		local reversedLength = #oddsGrouped - n
		local partOne = oddsGrouped[chanceIndex].TotalChance 
			* oddsGrouped[reversedLength + 1].TotalChance 
			* (luck - 1)

		local partTwo = 0
		for m = 1, reversedLength do
			partTwo += oddsGrouped[m].TotalChance
		end

		result += partOne / partTwo
	end

	return result
end

local function getFromRange(oddsRange: {number}, randomNumber: number): number
	for i = #oddsRange, 1, -1 do
		if randomNumber > oddsRange[i] then continue end
		return i
	end
end

local function inverseNormalCDF(x: number, trials: number, probability: number): number
	if x == 0 or x == 1 then
		return x == 0 and 0 or trials
	end

	local constants = {2.515517, 0.802853, 0.010328, 1.432788, 0.189269, 0.001308}

	local mean = trials * probability
	local variance = mean * (1 - probability)
	local scale = math.sqrt(variance)

	local t = math.sqrt(-2 * math.log(math.min(x, 1 - x)))
	local subphi = (constants[1] + constants[2] * t + constants[3] * t^2)
		/ (1 + constants[4] * t + constants[5] * t^2 + constants[6] * t^3)
	local phi = x > 0.5 and math.sqrt(-2 * math.log(1 - x)) - subphi or -1 * (math.sqrt(-2 * math.log(x)) - subphi)

	return math.clamp(math.floor(mean + scale * phi + 0.5),0,trials)
end

--------------------------------------||
--| 
--|		ERROR HANDLER FUNCTIONS
--| 
--------------------------------------||

local errorHandler = {}

errorHandler.OddsList = function(odds: any, isInit: boolean, oddsList: {number}) : boolean
	if typeof(odds) ~= 'table' or #odds == 0 or not odds then
		if isInit then
			error('[DynamicOdds]: Odds list must be a table and contain at least 1 number')
		end
		warn('[DynamicOdds]: Odds list must be a table and contain at least 1 number')
		return false
	end
	return true
end

errorHandler.Luck = function(luck: any, isInit: boolean, oddsList: {number}) : number
	luck = luck and luck or 1
	
	if typeof(luck) ~= 'number' then
		if luck ~= nil then
			warn('[DynamicOdds]: Luck multiplier must be a number')
		end
		return 1
	end
	return luck
end

errorHandler.OddsNaming = function(oddsNaming: any, isInit: boolean, oddsList: {number}) : {string}
	if oddsNaming ~= nil then
		if typeof(oddsNaming) ~= 'table' then
			warn('[DynamicOdds]: Odds naming list must be a table or nil')
			return nil
		elseif #oddsNaming ~= #oddsList then
			warn('[DynamicOdds]: Odds naming list must contain same elements count as Odds list')
			local newOddsNaming = {}
			for i, v in ipairs(oddsList) do
				if oddsNaming[i] ~= nil then
					newOddsNaming[i] = tostring(oddsNaming[i])
				else
					newOddsNaming[i] = 'Element '..i
				end
			end

			return newOddsNaming
		end
		
		return oddsNaming
	end
	
	return nil
end

errorHandler.ProbabilityLock = function(probabilityLock: any, isInit: boolean, oddsList: {number}) : {boolean}
	if probabilityLock ~= nil then
		if typeof(probabilityLock) ~= 'table' then
			warn('[DynamicOdds]: Probability lock list must be a table or nil')
			return nil
		end
		local is_normalized = true
		for i, v in pairs(probabilityLock) do
			if typeof(v) ~= "boolean" then
				if typeof(v) ~= "number" then 
					warn('[DynamicOdds]: Probability lock list must contain booleans or numbers (['..i..'] = '..v..')')
					return nil
				end
				is_normalized = false
				break
			end 	
		end
		
		local normalized_lock = {}
		if not is_normalized then
			for i, v in pairs(probabilityLock) do
				normalized_lock[v] = true
			end
		else
			for i, v in pairs(probabilityLock) do
				normalized_lock[i] = probabilityLock[i]
			end
		end
		
		for i = 1, #oddsList do
			if normalized_lock[i] == nil then
				normalized_lock[i] = false
			end
		end
		
		return normalized_lock
	end
	
	return nil
end

errorHandler.StaticGroups = function(staticGroups: any, isInit: boolean, oddsList: {number}) : {number}
	if staticGroups ~= nil then
		if typeof(staticGroups) == 'number' then
			return enumFunctions.StaticGroup[staticGroups](oddsList)
		elseif typeof(staticGroups) ~= 'table' then
			warn('[DynamicOdds]: Static influence groups list must be a table or nil')
			return nil
		elseif #staticGroups ~= #oddsList then
			warn('[DynamicOdds]: Static influence groups list must contain same elements count as Odds list')
			return nil
		end
	end

	if staticGroups then
		local lastGroup = 1
		for i, v in staticGroups do
			if typeof(v) ~= 'number' then
				warn('[DynamicOdds]: Element of static influence groups must be a number. (['..i..'] = '..v..')')
				return nil
			elseif v < 1 or v > #oddsList then
				warn('[DynamicOdds]: Element of static influence groups must be between 1 and '..#oddsList..'(['..i..'] = '..v..')')
				staticGroups[i] = math.clamp(v, 1, #oddsList)
			end

			if v < lastGroup then
				warn('[DynamicOdds]: Element of static influence cannot be lower than previous element (['..i..'] = '..v..')')
				staticGroups[i] = lastGroup
			elseif v % 1 > 0 then
				warn('[DynamicOdds]: Element of static influence must be an integer (['..i..'] = '..v..')')
				staticGroups[i] = v // 1
			end
			lastGroup = staticGroups[i]
		end
		
		return staticGroups
	end
	
	return nil
end

--------------------------------------||
--| 
--|			INIT FUNCTION
--| 
--------------------------------------||

function module.new(
	oddsRatioList: {number}, 
	luckMultiplier: number, 
	oddsNaming: {string}, 
	probabilityLock: {boolean} | {number}, 
	staticGroups: {number}
) : Odds
	
	errorHandler.OddsList(oddsRatioList, true)
	luckMultiplier = errorHandler.Luck(luckMultiplier, true, oddsRatioList)
	oddsNaming = errorHandler.OddsNaming(oddsNaming, true, oddsRatioList)
	probabilityLock = errorHandler.ProbabilityLock(probabilityLock, true, oddsRatioList)
	staticGroups = errorHandler.StaticGroups(staticGroups, true, oddsRatioList)
	
	local totalChance = 0
	for i, v in pairs(oddsRatioList) do totalChance += v end
	for i, v in pairs(oddsRatioList) do oddsRatioList[i] = v / totalChance end
	return setmetatable({
		original_odds = oddsRatioList, 
		odds_naming = oddsNaming,
		luck_multi = luckMultiplier, 
		static_groups = staticGroups,
		probability_lock = probabilityLock,
		_cache = {
			luck = luckMultiplier,
			odds = {}
		}
	}, Odds)
end

--------------------------------------||
--| 
--|			MAIN FUNCTIONS
--| 
--------------------------------------||

Odds.InfluencePower = function(self: Odds) : {number}
	local lockList = self.probability_lock or {}
	local staticList = self.static_groups or {}
	
	if staticList and #staticList ~= 0 then
		if lockList then
			for i, v in pairs(staticList) do
				staticList[i] = lockList[i] and 0 or v
			end
		end
		return staticList 
	end
	
	local oddsList = self.original_odds
	local highestOdd = 0
	local lowestOdd = 1
	for i, v in pairs(oddsList) do
		if lockList[i] then continue end
		highestOdd = v > highestOdd and v or highestOdd
		lowestOdd = v < lowestOdd and v or lowestOdd
	end
	
	local difference = math.log10(highestOdd/lowestOdd)
	local influenceList = {}
	local groupsCount = #oddsList - 1
	
	if difference == 0 then
		for i=1, #oddsList, 1 do
			table.insert(influenceList, 1)
		end
		return influenceList
	end
	for i, v in pairs(oddsList) do
		if lockList[i] then
			table.insert(influenceList, 0)
			continue
		end
		local influencePower = 1 + math.floor(math.log10(highestOdd/v)/difference * groupsCount)
		table.insert(influenceList, influencePower)
	end
	
	return influenceList
end

Odds.GroupByInfluence = function(self: Odds, getPower: boolean) : {}
	local lockList = self.probability_lock or {}
	local oddsList = self.original_odds
	local influenceList = self:InfluencePower()
	
	local influenceGroups = {}
	for i=0, #oddsList, 1 do
		if i == 0 and #lockList == 0 then continue end
		influenceGroups[i] = {
			Odds = {},
			TotalChance = 0
		}
	end
	for i, v in pairs(oddsList) do
		table.insert(influenceGroups[influenceList[i]].Odds, v)
		influenceGroups[influenceList[i]].TotalChance += v
	end
	for i, v in pairs(influenceGroups) do
		for index, value in pairs(v.Odds) do
			v.Odds[index] /= v.TotalChance
		end
	end
	return influenceGroups, getPower and influenceList or nil
end

Odds.Get = function(self: Odds, naming: boolean) : {number}
	naming = naming == nil and true or false
	local luckMulti = self.luck_multi
	local oddsGrouped, influencePower = self:GroupByInfluence(true)
	
	if #self._cache.odds ~= 0 and self._cache.luck == luckMulti then
		local cache = self._cache.odds
		local result = cache
		if naming and self.odds_naming then
			result = {}
			for i, v in ipairs(cache) do
				result[self.odds_naming[i]] = v
			end
		end
		
		return result
	end
	
	local newOdds = {}
	local newGroups = {}
	local totalChance = 0
	local prevChance = 0
	
	for i, v in pairs(oddsGrouped) do
		local chance = v.TotalChance
		if chance == 0 then
			continue
		end
		if i == 0 then
			newGroups[i] = chance
			continue
		elseif i ~= 1 then
			chance *= luckMulti
			chance += math.min(prevChance, 0)
		end
		
		chance -= oddsInfluence(oddsGrouped, i, luckMulti)
		prevChance = chance
		newGroups[i] = chance
	end
	local lockedGroup = newGroups[0] or 0
	for i, v in pairs(newGroups) do
		newGroups[i] = math.clamp(v, 0, 1)
		totalChance += i ~= 0 and newGroups[i] or 0
		if i == #oddsGrouped then
			newGroups[i] += 1 - totalChance - lockedGroup
		end
	end
	for i, v in pairs(influencePower) do
		local oddsGroup = oddsGrouped[v]
		table.insert(newOdds, oddsGroup.Odds[1] * newGroups[v])
		table.remove(oddsGroup.Odds, 1)
	end
	self._cache.luck = luckMulti
	self._cache.odds = newOdds
	local result = newOdds
	if naming and self.odds_naming then
		result = {}
		for i, v in ipairs(newOdds) do
			result[self.odds_naming[i]] = v
		end
	end
	return result
end

Odds.GetRange = function(self: Odds, naming: boolean) : {number}
	naming = naming == nil and true or false
	local oddsList = self:Get(false)
	
	local range = {}
	local totalChance = 0
	for i = #oddsList, 1, -1 do
		totalChance += oddsList[i]
		range[i] = totalChance
		if i == 1 then
			range[i] += 1 - totalChance
		end
	end
	
	local result = range
	if naming and self.odds_naming then
		result = {}
		for i, v in ipairs(range) do
			result[self.odds_naming[i]] = v
		end
	end
	return result
end

Odds.Display = function(self: Odds, isShort: boolean, naming: boolean) : {number}
	naming = naming == nil and true or false
	isShort = isShort == nil and true or false
	
	local oddsList = self:Get(false)
	local displayList = {}
	local namingAvailable = naming and self.odds_naming
	
	for i, v in pairs(oddsList) do
		local index = namingAvailable and self.odds_naming[i] or i
		
		if v <= 0 then
			displayList[index] = 'Unavailable'
			continue
		elseif v > PERCENT_THRESHOLD then
			displayList[index] = tostring(decimal.round(v*100, DECIMAL_POINTS))..'%'
			continue
		end
		displayList[index] = '1/'..(isShort and short(1/v) or commas(v))
	end
	
	return displayList
end

--------------------------------------||
--| 
--|			RANDOM FUNCTIONS
--| 
--------------------------------------||

Odds.Random = function(self: Odds, naming: boolean) : number
	naming = naming == nil and true or false
	
	local oddsRange = self:GetRange(false)
	local randomNumber = math.random()
	
	local result = getFromRange(oddsRange, randomNumber)
	return (naming and self.odds_naming) and self.odds_naming[result] or result
end

Odds.BulkRandom = function(self: Odds, bulkAmount: number, naming: boolean, legacy: boolean) : {number}
	naming = naming == nil and true or naming
	legacy = legacy ~= nil and legacy or false
	bulkAmount = bulkAmount or 1

	local totalBulk = 0
	local oddsRange = self:GetRange(false)
	local odds = self:Get(false)
	local result = {}
	local namingAvailable = naming and self.odds_naming
	for i=#oddsRange, 1, -1 do
		local randomResult = not legacy 
			and (oddsRange[i] == 1 and bulkAmount - totalBulk or inverseNormalCDF(math.random(), bulkAmount, odds[i])) 
			or 0
		result[namingAvailable and self.odds_naming[i] or i] = randomResult
		totalBulk += randomResult
	end
	if legacy then
		for i=1, bulkAmount do
			local randomNumber = math.random()
			local pickedNumber = getFromRange(oddsRange, randomNumber)
			
			result[namingAvailable and self.odds_naming[pickedNumber] or pickedNumber] += 1
		end
	end
	return result
end

--------------------------------------||
--| 
--|			LUCK MANIPULATIONS
--| 
--------------------------------------||

Odds.SetLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi = luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.AddLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi += luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.SubLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi -= luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.MulLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi *= luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.DivLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi /= luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.PowLuck = function(self: Odds, luckMultiplier: number) : Odds
	self.luck_multi ^= luckMultiplier
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

--------------------------------------||
--| 
--|			EXTRA MANIPULATIONS
--| 
--------------------------------------||

Odds.SetNaming = function(self: Odds, namingList: nil | {string}) : Odds
	local oddsList = self.original_odds
	self.odds_naming = errorHandler.OddsNaming(namingList, false, oddsList)
	return self
end

Odds.SetOdds = function(self: Odds, oddsList: {number}) : Odds
	if typeof(oddsList) ~= 'table' or #oddsList == 0 then
		warn('[DynamicOdds]: Odds list must be a table and contain at least 1 number')
		return self
	end
	
	local totalChance = 0
	for i, v in pairs(oddsList) do totalChance += v end
	for i, v in pairs(oddsList) do oddsList[i] = v / totalChance end
	
	self.original_odds = oddsList
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.AddOdds = function(self: Odds, oddsList: number | {number}) : Odds
	local newOdds = {}
	local totalNew = 0
	
	if not oddsList then return self end
	
	if typeof(oddsList) == 'table' then
		for i, v in pairs(oddsList) do
			table.insert(newOdds, v)
			totalNew += v
		end
	else
		table.insert(newOdds, oddsList)
		totalNew += oddsList
	end
	
	for i, v in pairs(self.original_odds) do
		self.original_odds[i] *= 1 - totalNew
	end
	for i, v in pairs(newOdds) do
		table.insert(self.original_odds, v)
	end
	
	table.sort(self.original_odds, function(a,b) return a > b end)
	
	if typeof(oddsList) == 'table' then
		for index, v in pairs(oddsList) do
			if typeof(index) ~= 'string' and not self.odds_naming then continue end
			table.insert(
				self.odds_naming,
				table.find(self.original_odds, v),
				index
			)
		end
	end

	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

--------------------------------------||
--| 
--|		  ADVANCED MANIPULATIONS
--| 
--------------------------------------||

Odds.ResetStaticGroups = function(self: Odds) : Odds
	self.static_groups = nil
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.SetStaticGroups = function(self: Odds, staticGroups: {number}) : Odds
	local oddsList = self.original_odds
	self.static_groups = errorHandler.StaticGroups(staticGroups, false, oddsList)
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.ClearProbabilityLock = function(self: Odds) : Odds
	self.probability_lock = nil
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

Odds.SetProbabilityLock = function(self: Odds, probabilityLockList: {number} | {boolean}) : Odds
	local oddsList = self.original_odds
	self.probability_lock = errorHandler.ProbabilityLock(probabilityLockList, false, oddsList)
	self._cache = {
		luck = self.luck_multi,
		odds = {}
	}
	return self
end

export type Odds = typeof(setmetatable({}::{
	_cache: {luck: number, odds: {number}},
	original_odds: {number},
	luck_multi: number,
	odds_naming: {string},
	probability_lock: {boolean},
	static_groups: {number}
}, Odds))

return module