--!strict
-- WalletGui builds the read-only currency panel shown in the middle of the
-- screen. It renders one row per registered currency with a live balance,
-- a search bar to filter currencies by name, and an A→Z / Z→A sort toggle.
-- The list scrolls when it overflows.
--
-- This is presentation only: it reads from WalletController and never mutates
-- economy state. Rows are created once and then shown/hidden and reordered in
-- place, so filtering and sorting allocate nothing per keystroke.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage.EconomyShared

local Types = require(EconomyShared.Types)
local CurrencyConfig = require(EconomyShared.CurrencyConfig)
local WalletController = require(script.Parent.WalletController)

type CurrencyId = Types.CurrencyId
type CurrencyDefinition = Types.CurrencyDefinition

local WalletGui = {}

-- Visual constants kept in one place for easy theming.
local ROW_HEIGHT = 36
local PANEL_SIZE = UDim2.fromOffset(360, 440)
local COLOR_BG = Color3.fromRGB(24, 26, 32)
local COLOR_PANEL = Color3.fromRGB(32, 35, 43)
local COLOR_ROW = Color3.fromRGB(40, 44, 54)
local COLOR_TEXT = Color3.fromRGB(235, 238, 245)
local COLOR_MUTED = Color3.fromRGB(150, 156, 168)
local COLOR_ACCENT = Color3.fromRGB(90, 140, 255)

-- Formats an integer balance with thousands separators (1234567 -> 1,234,567).
local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign, text = "-", string.sub(text, 2)
	end
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	formatted = (formatted:gsub("^,", ""))
	return sign .. formatted
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Per-row handle: the frame, its balance label, and its definition so the
-- controller can filter/sort/update without re-reading the instance tree.
type Row = {
	definition: CurrencyDefinition,
	frame: Frame,
	balanceLabel: TextLabel,
}

-- Builds the whole panel and wires search, sort and live balance updates.
-- Returns the ScreenGui so callers can keep or destroy it.
function WalletGui.mount(): ScreenGui
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EconomyWallet"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Centered panel.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = PANEL_SIZE
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	corner(panel, 12)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	-- Title.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = COLOR_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Currencies"
	title.Parent = panel

	-- Controls row: search box + sort toggle.
	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.LayoutOrder = 2
	controls.Size = UDim2.new(1, 0, 0, 32)
	controls.BackgroundTransparency = 1
	controls.Parent = panel

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.Size = UDim2.new(1, -76, 1, 0)
	searchBox.Position = UDim2.fromOffset(0, 0)
	searchBox.BackgroundColor3 = COLOR_BG
	searchBox.BorderSizePixel = 0
	searchBox.Font = Enum.Font.Gotham
	searchBox.TextSize = 14
	searchBox.TextColor3 = COLOR_TEXT
	searchBox.PlaceholderText = "Search currency..."
	searchBox.PlaceholderColor3 = COLOR_MUTED
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Parent = controls
	corner(searchBox, 8)
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 10)
	searchPad.Parent = searchBox

	local sortButton = Instance.new("TextButton")
	sortButton.Name = "Sort"
	sortButton.AnchorPoint = Vector2.new(1, 0)
	sortButton.Position = UDim2.fromScale(1, 0)
	sortButton.Size = UDim2.new(0, 68, 1, 0)
	sortButton.BackgroundColor3 = COLOR_ACCENT
	sortButton.BorderSizePixel = 0
	sortButton.Font = Enum.Font.GothamMedium
	sortButton.TextSize = 14
	sortButton.TextColor3 = COLOR_TEXT
	sortButton.AutoButtonColor = true
	sortButton.Text = "A → Z"
	sortButton.Parent = controls
	corner(sortButton, 8)

	-- Scrollable list of currency rows.
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.LayoutOrder = 3
	scroller.Size = UDim2.new(1, 0, 1, -80)
	scroller.BackgroundColor3 = COLOR_BG
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = COLOR_ACCENT
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = panel
	corner(scroller, 8)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scroller
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.PaddingLeft = UDim.new(0, 4)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.Parent = scroller

	-- Build one row per currency, indexed by id for O(1) balance updates.
	local rows: { Row } = {}
	local rowById: { [CurrencyId]: Row } = {}

	for _, definition in CurrencyConfig.all() do
		local frame = Instance.new("Frame")
		frame.Name = definition.id
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = COLOR_ROW
		frame.BorderSizePixel = 0
		frame.Parent = scroller
		corner(frame, 6)

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = frame

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = COLOR_TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = string.format("%s (%s)", definition.displayName, definition.abbreviation)
		nameLabel.Parent = frame

		local balanceLabel = Instance.new("TextLabel")
		balanceLabel.Size = UDim2.new(0.4, 0, 1, 0)
		balanceLabel.Position = UDim2.fromScale(0.6, 0)
		balanceLabel.BackgroundTransparency = 1
		balanceLabel.Font = Enum.Font.GothamBold
		balanceLabel.TextSize = 14
		balanceLabel.TextColor3 = COLOR_TEXT
		balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
		balanceLabel.Text = formatNumber(WalletController.getBalance(definition.id))
		balanceLabel.Parent = frame

		local row: Row = { definition = definition, frame = frame, balanceLabel = balanceLabel }
		rows[#rows + 1] = row
		rowById[definition.id] = row
	end

	-- Current view state.
	local query = ""
	local ascending = true

	-- Applies the active search + sort. Rows are shown/hidden and reordered
	-- via LayoutOrder; nothing is created or destroyed here.
	local function refresh()
		local visible: { Row } = {}
		for _, row in rows do
			local def = row.definition
			local matches = query == ""
				or string.find(string.lower(def.displayName), query, 1, true) ~= nil
				or string.find(def.id, query, 1, true) ~= nil
			row.frame.Visible = matches
			if matches then
				visible[#visible + 1] = row
			end
		end

		table.sort(visible, function(a, b)
			if ascending then
				return a.definition.displayName < b.definition.displayName
			end
			return a.definition.displayName > b.definition.displayName
		end)

		for index, row in visible do
			row.frame.LayoutOrder = index
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		query = string.lower(searchBox.Text)
		refresh()
	end)

	sortButton.Activated:Connect(function()
		ascending = not ascending
		sortButton.Text = if ascending then "A → Z" else "Z → A"
		refresh()
	end)

	-- Live balance updates from the server's replicated wallet.
	WalletController.onChanged(function(currency: CurrencyId, balance: number)
		local row = rowById[currency]
		if row then
			row.balanceLabel.Text = formatNumber(balance)
		end
	end)

	refresh()
	screenGui.Parent = playerGui
	return screenGui
end

return WalletGui
