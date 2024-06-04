
local frame = CreateFrame("Frame", "PITracker", UIParent)
PITracker = LibStub("AceAddon-3.0"):NewAddon(frame, "PITracker", "AceConsole-3.0")
PITracker.frame = frame

local table = table
local PI_SPELLID = 10060
local COMBATLOG_FILTER_RAID_PLAYERS = bit.bor(
	COMBATLOG_OBJECT_AFFILIATION_MINE,
	COMBATLOG_OBJECT_AFFILIATION_PARTY,
	COMBATLOG_OBJECT_AFFILIATION_RAID,
	COMBATLOG_OBJECT_REACTION_FRIENDLY,
	COMBATLOG_OBJECT_CONTROL_PLAYER,
	COMBATLOG_OBJECT_TYPE_PLAYER
)		
local TRACKED_CL_EVENTS = {
	damage = {
		SPELL_DAMAGE = true,
		SPELL_PERIODIC_DAMAGE = true,
		DAMAGE_SPLIT = true,
		DAMAGE_SHIELD = true,
	},
	healing = {
		SPELL_HEAL = true,
		SPELL_PERIODIC_HEAL = true,
	},
	aura = {
		SPELL_AURA_APPLIED = true,
		SPELL_AURA_REMOVED = true,
	}
}

-- http://lua-users.org/wiki/BinaryInsert
do
   local fcomp_default = function( a,b ) return a < b end
   function table.bininsert(t, value, fcomp)
      local fcomp = fcomp or fcomp_default
      local iStart,iEnd,iMid,iState = 1,#t,1,0
      while iStart <= iEnd do
         iMid = math.floor( (iStart+iEnd)/2 )
         if fcomp( value,t[iMid] ) then
            iEnd,iState = iMid - 1,0
         else
            iStart,iState = iMid + 1,1
         end
      end
      table.insert( t,(iMid+iState),value )
      return (iMid+iState)
   end
end

function PITracker:OnInitialize()
	if select(3, UnitClass("player")) ~= 5 then -- disable if not priest
		self:Disable()
		return
	end

	local L = PITrackerLocalization
	local profileDefault = {
		profile = {
			flavorText = L.FLAVOR_TEXT_DEFAULT,
			announcement = L.ANNOUNCEMENT_DEFAULT,
			isDecimalComma = false,
			isMuteStats = true,
		},
		char = {
			totalPICount = 0,
			damage = {},
			healing = {},
			pi_stats = {},
		}
	}
	local options = { 
		type = "group",
		args = {
			custom = {
				name = "Custom Options",
				type = "group",
				set = function(info, v) self.db.profile[info[#info]] = v end,
				get = function(info, ...) return self.db.profile[info[#info]] end,
				args = {
					flavorText = {
						name = L.FLAVOR_TEXT,
						type = "input",
						width = "double",
						order = 0,
						desc = L.FLAVOR_TEXT_DESC,
						multiline = 2
					},
					announcement = {
						name = L.ANNOUNCEMENT,
						type = "input",
						width = "double",
						order = 0,
						desc = L.ANNOUNCEMENT_DESC,
						multiline = 2
					},
					WHITESPACE = {
						name = "\n\n",
						type = "description",
						width = "full",
						order = 1,
						fontSize = "large",
					},
					isDecimalComma = {
						name = L.DECIMAL_COMMAS,
						type = "toggle",
						width = "double",
						order = 2,
						desc = L.DECIMAL_COMMAS_DESC
					},
					isMuteStats = {
						name = L.MUTE_STATS,
						type = "toggle",
						width = "double",
						order = 2,
						desc = L.MUTE_STATS_DESC
					},
					WHITESPACE2 = {
						name = "\n\n",
						type = "description",
						width = "full",
						order = 3,
						fontSize = "large",
					},
					resetButtons = {
						type = "group",
						name = "Manage Database",
						confirm = function(info, ...) return string.format("%s?", info.option.name) end,
						args = {
							resetRank = {
								name = L.RESET_RANK,
								type = "execute",
								desc = L.RESET_RANK_DESC,
								order = 4,
								func = function() self.db.char.pi_stats={} end,
							},
							resetAllStats = {
								name = L.RESET_ALL_STATS,
								type = "execute",
								desc = L.RESET_ALL_STATS_DESC,
								order = -1,
								func = function() 
											self.db.char.pi_stats={}
											self.db.char.damage={}
											self.db.char.healing={}
											self.db.char.totalPICount=0
										end,
							}
						}
					},

				}
			},
		}
	}

	self.db = LibStub("AceDB-3.0"):New("PITrackerDB", profileDefault, true)
	self.allstates = {}
	self.isPI = 0
	self.isEncounter = false
	self.isZoneSanctuary = false
	self.playerGUID = UnitGUID("player")
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	LibStub("AceConfig-3.0"):RegisterOptionsTable("PITracker", options.args.custom)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("PITracker Profiles", options.args.profiles)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("PITracker","PI Tracker")
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("PITracker Profiles", "Profiles", "PI Tracker")
	self:RegisterChatCommand("pitracker", "SlashCommand")
	self:RegisterChatCommand("pi", "SlashCommand")
end

function PITracker:OnEnable()
	self.isZoneSanctuary = "sanctuary" == select(1, GetZonePVPInfo())
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:SetScript( "OnEvent", function(self, event, ...) 
		self[event](self, ...) 
	end)
end

function PITracker:OnDisable()
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
end

function PITracker:SlashCommand(...)
	-- https://github.com/Stanzilla/WoWUIBugs/issues/89
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end

function PITracker:COMBAT_LOG_EVENT_UNFILTERED(...)
	if not self.isZoneSanctuary then
		local cl = {CombatLogGetCurrentEventInfo()}
		local _,subevent,_,_,_,sourceFlags = unpack(cl)
		if CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_RAID_PLAYERS) then
				if TRACKED_CL_EVENTS["damage"][subevent] and self.isPI then
					self:Track("damage", unpack(cl))
				elseif TRACKED_CL_EVENTS["healing"][subevent] and self.isPI then
					self:Track("healing", unpack(cl))
				elseif TRACKED_CL_EVENTS["aura"][subevent] then
					self[subevent](self, unpack(cl))
				end
		end
	end
end

function PITracker:ZONE_CHANGED_NEW_AREA(...)
	self.isZoneSanctuary = "sanctuary" == select(1, GetZonePVPInfo())
end

function PITracker:SPELL_AURA_APPLIED(...)
	local _,_,_,sourceGUID,_,_,_,destGUID,destName,_,_,spellID = ...
	if (sourceGUID == self.playerGUID) and (spellID == PI_SPELLID) then
		self.isPI = self.isPI + 1
		self.allstates[destGUID] = {
			damage = 0,
			healing = 0,
		}
		SendChatMessage(self.db.profile.announcement, "WHISPER", nil, destName)
	end
end

function PITracker:SPELL_AURA_REMOVED(...)
	local _,_,_,sourceGUID,_,_,_,destGUID,destName,_,_,spellID = ...
	if (sourceGUID == self.playerGUID) and (spellID == PI_SPELLID) then
		local statsMsgFmt = "Times PI'd: %d. This rank: %.0f. Best rank: %.0f."
		local newStats = self.db.char.pi_stats[destGUID] and self.db.char.pi_stats[destGUID] or {piCount=0, best=0, avg=0}
		local spellType = self.allstates[destGUID].damage >= self.allstates[destGUID].healing and "damage" or "healing"

		local activeList = self.db.char[spellType]
		local total = self.allstates[destGUID][spellType]
		local dmgMsg = PITrackerLocalization.RESPONSE_FORMAT:format(
											self:format_int(total), spellType, self.db.profile.flavorText)
		SendChatMessage(dmgMsg, "WHISPER", nil, destName)
		newStats.piCount = newStats.piCount + 1
		self.db.char.totalPICount = self.db.char.totalPICount + 1

		if (total > 0) then
			local i = table.bininsert(activeList, total)
			local rank = ceil(i / #activeList * 100)
			newStats.best = rank > newStats.best and rank or newStats.best
			newStats.avg = ceil(newStats.avg + (rank - newStats.avg) / newStats.piCount)
			local statsMsg = statsMsgFmt:format(newStats.piCount, rank, newStats.best)
			if not self.db.profile.isMuteStats then
				SendChatMessage(statsMsg, "WHISPER", nil, destName)
			end
		end


		self.isPI = self.isPI - 1
		self.db.char.pi_stats[destGUID] = newStats
		self.allstates[destGUID] = nil
	end
end

function PITracker:Track(spellType, ...)
	local sourceGUID = select(4, ...)
	local amount, over = select(15, ...)
	if self.allstates[sourceGUID] then
		local previous = self.allstates[sourceGUID][spellType]
		self.allstates[sourceGUID][spellType] = previous + amount - over
	end
end


function PITracker:format_int(number)
	local decimalSym = self.db.profile.isDecimalComma and '.' or ','
	local _, _, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
	int = int:reverse():gsub("(%d%d%d)", "%1"..decimalSym)
	if self.db.profile.isDecimalComma and #fraction>1 then
	    fraction = ","..fraction:sub(2)
	end
	return minus .. int:reverse():gsub("^"..decimalSym, "") .. fraction
end
