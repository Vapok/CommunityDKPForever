local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

-- UX §7.1: bar geometry shared by ClassGraph() and ClassGraph_Update(). 200 px keeps a 100% bar
-- (plus its % label) below the §7.3 divider at y = -192 on ConfigTab1.
local BAR_MAX_HEIGHT = 200
local BAR_WIDTH = 25

function CommDKP:ClassGraph()

	local graph;

	graph = CreateFrame("Frame", "CommDKPClassIcons", CommDKP.ConfigTab1, "BackdropTemplate")

	graph:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 0, 0)
	CommDKP:SetBackdropRole(graph, "Clear")
	graph:SetSize(460, 495)

	-- UX §7.3: subtle 1px gold divider between the filter checkboxes and the class graph.
	graph.divider = CommDKP.ConfigTab1:CreateTexture(nil, "ARTWORK")
	graph.divider:SetPoint("TOPLEFT", CommDKP.ConfigTab1, "TOPLEFT", 10, -192)
	graph.divider:SetPoint("TOPRIGHT", CommDKP.ConfigTab1, "TOPRIGHT", -10, -192)
	graph.divider:SetHeight(1)
	graph.divider:SetColorTexture(1, 0.82, 0, 0.35)

	local icons = {}
	graph.icons = icons;
	local classCount = {}
	local perc_height = {}
	local perc = {}

	for k, v in pairs(core.classes) do
		local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), v)
		if classSearch and #classSearch > 0 then
			tinsert(classCount, #classSearch)
			local classPerc = CommDKP_round(#classSearch / #CommDKP:GetTable(CommDKP_DKPTable, true), 4);
			tinsert(perc, classPerc * 100)
			local adjustBar = BAR_MAX_HEIGHT * classPerc;
			tinsert(perc_height, adjustBar)
		else
			tinsert(classCount, 0)
			local classPerc = 0;
			tinsert(perc, 0)
			local adjustBar = 3;
			tinsert(perc_height, adjustBar)
		end
	end

	for i=1, 9 do
		graph.icons[i] = graph:CreateTexture(nil, "OVERLAY", nil);   -- Title Bar Texture
		if i==1 then
	  		graph.icons[i]:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", 74, 40);
		else
			graph.icons[i]:SetPoint("LEFT", graph.icons[i-1], "RIGHT", 15, 0);
		end
  		graph.icons[i]:SetColorTexture(0, 0, 0, 1)
  		graph.icons[i]:SetSize(28, 28);

		graph.icons[i].bar = CreateFrame("Frame", "CommDKP"..i.."Graph", graph, "BackdropTemplate")
  		
		graph.icons[i].bar:SetPoint("BOTTOM", icons[i], "TOP", 0, 5)
		CommDKP:SetBackdropRole(graph.icons[i].bar, nil, "Clear")
  		graph.icons[i].bar:SetSize(BAR_WIDTH, perc_height[i] or 3)
  		CommDKP:ApplyBackdrop(graph.icons[i].bar, "GraphBar")
  		graph.icons[i]:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes");

  		local c = CommDKP:GetCColors(core.classes[i])
		graph.icons[i].bar:SetBackdropColor(c.r, c.g, c.b, 1)	-- data color (class color; AD-6.3)

		graph.icons[i].percentage = graph.icons[i].bar:CreateFontString(nil, "OVERLAY")
		graph.icons[i].percentage:SetPoint("BOTTOM", graph.icons[i].bar, "TOP", 0, 3)
		graph.icons[i].percentage:SetFontObject("CommDKPSmallCenter")
		graph.icons[i].percentage:SetText(CommDKP_round(perc[i] or 0, 1).."%")
		graph.icons[i].percentage:SetTextColor(1, 1, 1, 1)

		graph.icons[i].count = graph.icons[i].bar:CreateFontString(nil, "OVERLAY")
		graph.icons[i].count:SetPoint("BOTTOM", graph.icons[i].bar, "BOTTOM", 0, -55)
		graph.icons[i].count:SetFontObject("CommDKPSmallCenter")
		graph.icons[i].count:SetText(classCount[i] or 0)
		graph.icons[i].count:SetTextColor(1, 1, 1, 1)

		local className = core.classes[i] or "nil";

		local coords = CLASS_ICON_TCOORDS[className]
		
		graph.icons[i]:SetTexCoord(unpack(coords))

		--CommDKP.ConfigTab2.header:SetScale(1.2)
	end

	return graph;
end

function CommDKP:ClassGraph_Update()
	local classCount = {}
	local perc_height = {}
	local perc = {}

	for k, v in pairs(core.classes) do
		local classSearch = CommDKP:Table_Search(CommDKP:GetTable(CommDKP_DKPTable, true), v)
		if classSearch and #classSearch > 0 then
			tinsert(classCount, #classSearch)
			local classPerc = CommDKP_round(#classSearch / #CommDKP:GetTable(CommDKP_DKPTable, true), 4);
			tinsert(perc, classPerc * 100)
			local adjustBar = BAR_MAX_HEIGHT * classPerc;
			tinsert(perc_height, adjustBar)
		else
			tinsert(classCount, 0)
			local classPerc = 0;
			tinsert(perc, 0)
			local adjustBar = 3;
			tinsert(perc_height, adjustBar)
		end
	end

	for i = 1, 9 do
		local icon = core.ClassGraph.icons[i]
		if icon then
			icon.bar:SetSize(BAR_WIDTH, perc_height[i] or 3)
			icon.percentage:SetText(CommDKP_round(perc[i] or 0, 1).."%")
			icon.count:SetText(classCount[i] or 0)
		end
	end
end
