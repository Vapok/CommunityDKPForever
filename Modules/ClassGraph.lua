local _, core = ...;
local _G = _G;
local CommDKP = core.CommDKP;
local L = core.L;

local W = CommDKP.Widgets

-- Bar geometry shared by ClassGraph() and ClassGraph_Update(). UX §12.3.2: the graph lives in the 548 x 288
-- Class Distribution card (260 px body), so a 100% bar (150) + icon + labels stays inside it.
local BAR_MAX_HEIGHT = 150
local BAR_WIDTH = 25

function CommDKP:ClassGraph()

	local graph;
	local host = (CommDKP.ConfigTab1.GraphCard and CommDKP.ConfigTab1.GraphCard.Body) or CommDKP.ConfigTab1

	graph = CreateFrame("Frame", "CommDKPClassIcons", host, "BackdropTemplate")

	graph:SetAllPoints(host)
	CommDKP:SetBackdropRole(graph, "Clear")

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
	  		graph.icons[i]:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", 85, 30);   -- 9 x 28 + 8 x 15 = 372 px, centered in the body
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
		graph.icons[i].bar.Edges = CommDKP:CreatePixelBorder(graph.icons[i].bar, (core.Palette or core.Palettes.Forever).trimQuiet)

		graph.icons[i].percentage = W.CreateText(graph.icons[i].bar, "body", CommDKP_round(perc[i] or 0, 1).."%", "CENTER")
		graph.icons[i].percentage:SetPoint("BOTTOM", graph.icons[i].bar, "TOP", 0, 3)

		graph.icons[i].count = W.CreateText(graph.icons[i].bar, "caption", classCount[i] or 0, "CENTER", "textMuted")
		graph.icons[i].count:SetPoint("TOP", graph.icons[i], "BOTTOM", 0, -4)

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
