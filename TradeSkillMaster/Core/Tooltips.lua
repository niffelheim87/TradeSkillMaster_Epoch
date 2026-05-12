-- ------------------------------------------------------------------------------ --
--                                TradeSkillMaster                                --
--                http://www.curse.com/addons/wow/tradeskill-master               --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- This file contains all the code for the new tooltip options

local TSM = select(2, ...)
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster") -- loads the localization table
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries
local lib = TSMAPI
local tooltipLib = LibStub("LibExtraTip-1")
local moduleObjects = TSM.moduleObjects
local moduleNames = TSM.moduleNames

local private = {}
TSMAPI:RegisterForTracing(private, "TradeSkillMaster.Tooltips_private")
private.tooltipInfo = {}

-- **************************************************************************
--                            LibExtraTip Functions
-- **************************************************************************

function TSM:SetupTooltips()
	-- tooltipLib:AddCallback({type = "battlepet", callback = private.LoadTooltip})
	tooltipLib:AddCallback({type = "item", callback = private.LoadTooltip})
	tooltipLib:RegisterTooltip(GameTooltip)
	tooltipLib:RegisterTooltip(ItemRefTooltip)
	-- tooltipLib:RegisterTooltip(BattlePetTooltip)
	local orig = OpenMailAttachment_OnEnter
	OpenMailAttachment_OnEnter = function(self, index)
		private.lastMailTooltipUpdate = private.lastMailTooltipUpdate or 0
		if private.lastMailTooltipIndex ~= index or private.lastMailTooltipUpdate + 0.1 < GetTime() then
			private.lastMailTooltipUpdate = GetTime()
			private.lastMailTooltipIndex = index
			orig(self, index)
		end
	end
end

local tooltipLines = {lastUpdate = 0, modifier=0}
local function GetTooltipLines(itemString, quantity)
	local modifier = (IsShiftKeyDown() and 4 or 0) + (IsAltKeyDown() and 2 or 0) + (IsControlKeyDown() and 1 or 0)
	if modifier ~= tooltipLines.modifier then
		tooltipLines.modifier = modifier
		tooltipLines.lastUpdate = 0
	end
	if tooltipLines.itemString ~= itemString or tooltipLines.quantity ~= quantity or tooltipLines.modifier ~= modifier or (tooltipLines.lastUpdate + 0.5) < GetTime() then
		wipe(tooltipLines)
		for _, moduleName in ipairs(moduleNames) do
			if moduleObjects[moduleName].GetTooltip then
				local moduleLines = moduleObjects[moduleName]:GetTooltip(itemString, quantity)
				if type(moduleLines) ~= "table" then moduleLines = {} end
				for _, line in ipairs(moduleLines) do
					tinsert(tooltipLines, line)
				end
			end
		end
		tooltipLines.itemString = itemString
		tooltipLines.quantity = quantity
		tooltipLines.lastUpdate = GetTime()
	end
	return tooltipLines
end

-- Tabla de distribución de DE por rango de ilvl (items de rareza Uncommon = rarity 2)
-- Formato: {ilvlMin, ilvlMax, itemIDPolvo, minPolvo, maxPolvo, %Polvo, itemIDEsencia, minEsencia, maxEsencia, %Esencia, itemIDShard, %Shard}
local deDistribution = {
    {1,  15,  10940, 1, 2, 80, 10938, 1, 2, 20, nil,   0},  -- Strange Dust 1-2, Lesser Magic Essence 1-2 (confirmado)
    {16, 20,  10940, 2, 3, 75, 10939, 1, 2, 20, 10978, 5},  -- Strange Dust 2-3 (confirmado), Greater Magic Essence, Small Glimmering Shard
    {21, 25,  10940, 4, 6, 75, 10998, 1, 2, 15, 10978, 10},
    {26, 30,  11083, 1, 2, 75, 11082, 1, 2, 20, 11084, 5},
    {31, 35,  11083, 2, 5, 75, 11134, 1, 2, 20, 11138, 5},
    {36, 40,  11137, 1, 2, 75, 11135, 1, 2, 20, 11139, 5},
    {41, 45,  11137, 2, 5, 75, 11174, 1, 2, 20, 11177, 5},
    {46, 50,  11176, 1, 2, 75, 11175, 1, 2, 20, 11178, 5},
    {51, 55,  11176, 2, 5, 75, 16202, 1, 2, 20, 14343, 5},
    {56, 60,  16204, 1, 2, 75, 16203, 1, 2, 20, 14344, 5},
    {61, 65,  16204, 2, 5, 75, 16203, 2, 3, 20, 14344, 5},
}

-- Tabla de distribución de DE para azules (rarity 3)
-- Formato: {ilvlMin, ilvlMax, itemIDShard1, %Shard1, itemIDShard2, %Shard2}
-- Shard2 es Nexus Crystal en rangos altos, nil si no aplica
local deDistributionBlue = {
    {1,  25,  10978, 100, nil,   0},     -- Small Glimmering Shard (confirmado ilvl 25)
    {26, 30,  11084, 100, nil,   0},     -- Large Glowing Shard
    {31, 35,  11138, 100, nil,   0},     -- Small Radiant Shard
    {36, 45,  11139, 100, nil,   0},     -- Large Radiant Shard
    {46, 55,  14343, 100, nil,   0},     -- Small Brilliant Shard
    {56, 65,  14344, 99.5, 20725, 0.5}, -- Large Brilliant Shard + Nexus Crystal (confirmado ilvl 60)
}

-- Tabla de distribución de DE para épicos (rarity 4)
-- Formato: {ilvlMin, ilvlMax, itemIDShard1, %Shard1, itemIDShard2, %Shard2}
local deDistributionEpic = {
    {1,  45,  14343, 100, nil,  0},  -- Small Brilliant Shard
    {46, 55,  14344, 100, nil,  0},  -- Large Brilliant Shard
    {56, 65,  20725, 100, nil,  0},  -- Nexus Crystal (confirmado ilvl 63)
}

local function InjectDEDistribution(tipFrame, itemString, r, g, b)
    local _, _, rarity, ilvl = GetItemInfo(itemString)
    if not ilvl then return end

    -- Uncommon (verde)
    if rarity == 2 then
        for _, d in ipairs(deDistribution) do
            if ilvl >= d[1] and ilvl <= d[2] then
                local dName = GetItemInfo(d[3]) or "Dust"
                local eName = d[7] and (GetItemInfo(d[7]) or "Essence")
                local sName = d[11] and (GetItemInfo(d[11]) or "Shard")

                tooltipLib:AddLine(tipFrame, "  Disenchant Distribution:", r / 255, g / 255, b / 255, TSM.db.profile.embeddedTooltip)
                tooltipLib:AddDoubleLine(tipFrame, "    |cffffffff" .. dName .. " (" .. d[4] .. "-" .. d[5] .. ")|r", "|cffffff00" .. d[6] .. "%|r", 1, 1, 1, 1, 1, 1, TSM.db.profile.embeddedTooltip)
                if eName then
                    tooltipLib:AddDoubleLine(tipFrame, "    |cff1eff00" .. eName .. " (" .. d[8] .. "-" .. d[9] .. ")|r", "|cffffff00" .. d[10] .. "%|r", 1, 1, 1, 1, 1, 1, TSM.db.profile.embeddedTooltip)
                end
                if sName and d[12] > 0 then
                    tooltipLib:AddDoubleLine(tipFrame, "    |cff0070dd" .. sName .. " (1-1)|r", "|cffffff00" .. d[12] .. "%|r", 1, 1, 1, 1, 1, 1, TSM.db.profile.embeddedTooltip)
                end
                break
            end
        end

    -- Rare (azul) o Epic (morado)
    elseif rarity == 3 or rarity == 4 then
        local table = rarity == 3 and deDistributionBlue or deDistributionEpic
        for _, d in ipairs(table) do
            if ilvl >= d[1] and ilvl <= d[2] then
                local s1Name = GetItemInfo(d[3]) or "Shard"
                local s2Name = d[5] and (GetItemInfo(d[5]) or "Nexus Crystal")

                tooltipLib:AddLine(tipFrame, "  Disenchant Distribution:", r / 255, g / 255, b / 255, TSM.db.profile.embeddedTooltip)
                tooltipLib:AddDoubleLine(tipFrame, "    |cff0070dd" .. s1Name .. " (1-1)|r", "|cffffff00" .. d[4] .. "%|r", 1, 1, 1, 1, 1, 1, TSM.db.profile.embeddedTooltip)
                if s2Name and d[6] > 0 then
                    tooltipLib:AddDoubleLine(tipFrame, "    |cffa335ee" .. s2Name .. " (1-1)|r", "|cffffff00" .. d[6] .. "%|r", 1, 1, 1, 1, 1, 1, TSM.db.profile.embeddedTooltip)
                end
                break
            end
        end
    end
end

function private.LoadTooltip(tipFrame, link, quantity)
    local itemString = TSMAPI:GetItemString(link)
    if not itemString then return end
    local lines = GetTooltipLines(itemString, quantity)

    local r, g, b = unpack(TSM.db.profile.design.inlineColors.tooltip or { 130, 130, 250 })

    -- Determinar si el item es desencantable (arma/armadura verde, azul o epico)
    local _, _, rarity, ilvl, _, iType = GetItemInfo(itemString)
    local WEAPON, ARMOR = GetAuctionItemClasses()
    local isDisenchantable = ilvl and rarity and iType
        and (iType == ARMOR or iType == WEAPON)
        and (rarity >= 2 and rarity <= 4)

    -- Si hay lineas de precio O el item es desencantable, mostramos el bloque TSM
    if #lines > 0 or isDisenchantable then
        tooltipLib:AddLine(tipFrame, " ", 1, 1, 0, TSM.db.profile.embeddedTooltip)

        local deInjected = false

        -- Renderizar las lineas normales de TSM, inyectando distribucion DE tras la linea de Disenchant Value
        for i = 1, #lines do
            local lineData = lines[i]

            if not deInjected and TSM.db.profile.deTooltip then
                local leftText = type(lineData) == "table" and lineData.left or lineData
                if leftText and leftText:find("Disenchant") and not leftText:find("Distribution") then
                    InjectDEDistribution(tipFrame, itemString, r, g, b)
                    deInjected = true
                end
            end

            if type(lineData) == "table" then
                tooltipLib:AddDoubleLine(tipFrame, lineData.left, lineData.right, r / 255, g / 255, b / 255, r / 255, g / 255, b / 255, TSM.db.profile.embeddedTooltip)
            else
                tooltipLib:AddLine(tipFrame, lineData, r / 255, g / 255, b / 255, TSM.db.profile.embeddedTooltip)
            end
        end

        -- Si no hubo linea de Disenchant Value (sin precios escaneados) pero el item
        -- es desencantable y la opcion esta activada, inyectamos la distribucion igualmente
        if not deInjected and isDisenchantable and TSM.db.profile.deTooltip then
            InjectDEDistribution(tipFrame, itemString, r, g, b)
        end

        tooltipLib:AddLine(tipFrame, " ", 1, 1, 0, TSM.db.profile.embeddedTooltip)
    end
end


-- **************************************************************************
--                             TSM Tooltip Options
-- **************************************************************************

function TSM:RegisterTooltipInfo(module, info)
	info = CopyTable(info)
	info.module = module
	tinsert(private.tooltipInfo, info)
end

function TSMAPI:GetMoneyCoinsTooltip()
	return TSM.db.profile.moneyCoinsTooltip
end

local loadTooltipOptionsTab
function TSM:LoadTooltipOptions(parent)
	local tabs = {}
	local next = next

	for _, info in ipairs(private.tooltipInfo) do
		tinsert(tabs, { text = info.module, value = info.module })
	end

	if next(tabs) then
		sort(tabs, function(a, b)
			return a.text < b.text
		end)
	end

	tinsert(tabs, 1, { text = L["General"], value = "Help" })

	local tabGroup = AceGUI:Create("TSMTabGroup")
	tabGroup:SetLayout("Fill")
	tabGroup:SetTabs(tabs)
	tabGroup:SetCallback("OnGroupSelected", function(_, _, value)
		tabGroup:ReleaseChildren()
		if value == "Help" then
			private:DrawTooltipHelp(tabGroup)
		else
			for _, info in ipairs(private.tooltipInfo) do
				if info.module == value then
					info.callback(tabGroup, loadTooltipOptionsTab and loadTooltipOptionsTab.tooltip)
				end
			end
		end
	end)
	parent:AddChild(tabGroup)

	tabGroup:SelectTab(loadTooltipOptionsTab and loadTooltipOptionsTab.module or "Help")
end

function private:DrawTooltipHelp(container)
	local priceSources = TSMAPI:GetPriceSources()
	priceSources["Crafting"] = nil
	priceSources["VendorBuy"] = nil
	priceSources["VendorSell"] = nil
	priceSources["Disenchant"] = nil
	local page = {
		{
			-- scroll frame to contain everything
			type = "ScrollFrame",
			layout = "List",
			children = {
				{
					type = "InlineGroup",
					layout = "flow",
					title = L["General Options"],
					children = {
						{
							type = "Label",
							text = L["Display prices in tooltips as:"],
							relativeWidth = 0.25,
						},
						{
							type = "CheckBox",
							label = L["Coins:"],
							relativeWidth = 0.09,
							settingInfo = {TSM.db.profile, "moneyCoinsTooltip"},
							callback = function(_, _, value)
								if value == true then
									TSM.db.profile.moneyTextTooltip = false
								end
								container:ReloadTab()
							end,
						},
						{
							type = "Label",
							relativeWidth = 0.22,
							text = TSMAPI:FormatTextMoneyIcon(3451267, "|cffffffff", false, true),
						},
						{
							type = "CheckBox",
							label = L["Text:"],
							relativeWidth = 0.09,
							settingInfo = {TSM.db.profile, "moneyTextTooltip"},
							callback = function(_, _, value)
								if value == true then
									TSM.db.profile.moneyCoinsTooltip = false
								end
								container:ReloadTab()
							end,
						},
						{
							type = "Label",
							text = TSMAPI:FormatTextMoney(3451267, "|cffffffff", false, true),
						},
						{
							type = "HeadingLine",
						},
						{
							type = "CheckBox",
							label = L["Embed TSM Tooltips"],
							settingInfo = {TSM.db.profile, "embeddedTooltip"},
							tooltip = L["If checked, TSM's tooltip lines will be embedded in the item tooltip. Otherwise, it will show as a separate box below the item's tooltip."],
						},
						{
							type = "CheckBox",
							label = L["Display Group / Operation Info in Tooltips"],
							settingInfo = {TSM.db.profile, "tooltip"},
						},
						{
							type = "CheckBox",
							label = L["Display vendor buy price in tooltip."],
							settingInfo = { TSM.db.profile, "vendorBuyTooltip" },
							tooltip = L["If checked, the price of buying the item from a vendor is displayed."],
						},
						{
							type = "CheckBox",
							label = L["Display vendor sell price in tooltip."],
							settingInfo = { TSM.db.profile, "vendorSellTooltip" },
							tooltip = L["If checked, the price of selling the item to a vendor displayed."],
						},
					},
				},
				{
					type = "InlineGroup",
					layout = "flow",
					title = L["Destroy Values"],
					children = {
						{
							type = "Dropdown",
							label = L["Destroy Value Source:"],
							settingInfo = {TSM.db.profile, "destroyValueSource"},
							list = priceSources,
							relativeWidth = 0.5,
							tooltip = L["Select the price source for calculating destroy values."],
						},
						{
							type = "CheckBox",
							label = L["Display Detailed Destroy Tooltips"],
							settingInfo = { TSM.db.profile, "detailedDestroyTooltip" },
							relativeWidth = 0.49,
							tooltip = L["If checked, a detailed list of items which an item destroys into will be displayed below the destroy value in the tooltip."],
						},
						{
							type = "HeadingLine",
						},
						{
							type = "CheckBox",
							label = L["Display mill value in tooltip."],
							settingInfo = { TSM.db.profile, "millTooltip" },
							relativeWidth = 0.5,
							tooltip = L["If checked, the mill value of the item will be shown. This value is calculated using the average market value of materials the item will mill into."],
						},
						{
							type = "CheckBox",
							label = L["Display prospect value in tooltip."],
							settingInfo = { TSM.db.profile, "prospectTooltip" },
							relativeWidth = 0.5,
							tooltip = L["If checked, the prospect value of the item will be shown. This value is calculated using the average market value of materials the item will prospect into."],
						},
						{
							type = "CheckBox",
							label = L["Display disenchant value in tooltip."],
							settingInfo = { TSM.db.profile, "deTooltip" },
							relativeWidth = 0.5,
							tooltip = L["If checked, the disenchant value of the item will be shown. This value is calculated using the average market value of materials the item will disenchant into."],
						},
					},
				},
			},
		},
	}
	
	if next(TSM.db.global.customPriceSources) then
		local inlineGroup = {
			type = "InlineGroup",
			layout = "flow",
			title = L["Custom Price Sources"],
			children = {
				{
					type = "Label",
					text = L["Custom price sources to display in item tooltips:"],
					relativeWidth = 1,
				},
			},
		}
		for name in pairs(TSM.db.global.customPriceSources) do
			local checkbox = {
				type = "CheckBox",
				label = name,
				relativeWidth = 0.5,
				settingInfo = { TSM.db.global.customPriceTooltips, name },
				tooltip = L["If checked, this custom price will be displayed in item tooltips."],
			}
			tinsert(inlineGroup.children, checkbox)
		end
		tinsert(page[1].children, inlineGroup)
	end

	TSMAPI:BuildPage(container, page)
end
