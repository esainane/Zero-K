VFS.Include("LuaRules/Configs/customcmds.h.lua")

local widgetName = "Reclaim Highlight"

function widget:GetInfo()
  return {
    name      = widgetName,
    desc      = "Highlights clusters of reclaimable material",
    author    = "ivand, refactored by esainane",
    date      = "2020",
    license   = "public",
    layer     = 0,
    enabled   = false  --  loaded by default?
  }
end

local screenx, screeny

local gaiaTeamId = Spring.GetGaiaTeamID()
local myAllyTeamID
local function UpdateTeamAndAllyTeamID()
	myAllyTeamID = Spring.GetMyAllyTeamID()
end

local Benchmark = VFS.Include("LuaRules/Gadgets/Include/Benchmark.lua")
local benchmark = Benchmark.new()

local scanInterval = 1 * Game.gameSpeed
local scanForRemovalInterval = 10 * Game.gameSpeed --10 sec

local minDistance = 300
local minSqDistance = minDistance^2
local minPoints = 2
local minFeatureMetal = 8 --flea

local knownFeatures = {}

local featureNeighborsMatrix = {}
local function UpdateFeatureNeighborsMatrix(fID, added, posChanged, removed)
	local fInfo = knownFeatures[fID]

	if added then
		featureNeighborsMatrix[fID] = {}
		for fID2, fInfo2 in pairs(knownFeatures) do
			if fID2 ~= fID then --don't include self into featureNeighborsMatrix[][]
				local sqDist = (fInfo.x - fInfo2.x)^2 + (fInfo.z - fInfo2.z)^2
				if sqDist <= minSqDistance then
					featureNeighborsMatrix[fID][fID2] = true
					featureNeighborsMatrix[fID2][fID] = true
				end
			end
		end
	end

	if removed then
		for fID2, _ in pairs(featureNeighborsMatrix[fID]) do
			featureNeighborsMatrix[fID2][fID] = nil
			featureNeighborsMatrix[fID][fID2] = nil
		end
	end

	if posChanged then
		UpdateFeatureNeighborsMatrix(fID, false, false, true) --remove
		UpdateFeatureNeighborsMatrix(fID, true, false, false) --add again
	end
end

local featureClusters = {}

local E2M = 2 / 70 --solar ratio

local featuresUpdated = false
local clusterMetalUpdated = false

local function UpdateFeatures(gf)
	benchmark:Enter("UpdateFeatures")
	featuresUpdated = false
	clusterMetalUpdated = false
	benchmark:Enter("UpdateFeatures 1loop")
	for _, fID in ipairs(Spring.GetAllFeatures()) do
		local metal, _, energy = Spring.GetFeatureResources(fID)
		metal = metal + energy * E2M

		if (not knownFeatures[fID]) and (metal >= minFeatureMetal) then --first time seen
			knownFeatures[fID] = {}
			knownFeatures[fID].lastScanned = gf

			local fx, _, fz = Spring.GetFeaturePosition(fID)
			local fy = Spring.GetGroundHeight(fx, fz)
			knownFeatures[fID].x = fx
			knownFeatures[fID].y = fy
			knownFeatures[fID].z = fz

			knownFeatures[fID].isGaia = (Spring.GetFeatureTeam(fID) == gaiaTeamId)
			knownFeatures[fID].height = Spring.GetFeatureHeight(fID)
			knownFeatures[fID].drawAlt = ((fy > 0 and fy) or 0) + knownFeatures[fID].height + 10

			knownFeatures[fID].metal = metal

			UpdateFeatureNeighborsMatrix(fID, true, false, false)
			featuresUpdated = true
		end

		if knownFeatures[fID] and gf - knownFeatures[fID].lastScanned >= scanInterval then
			knownFeatures[fID].lastScanned = gf

			local fx, _, fz = Spring.GetFeaturePosition(fID)
			local fy = Spring.GetGroundHeight(fx, fz)

			if knownFeatures[fID].x ~= fx or knownFeatures[fID].y ~= fy or knownFeatures[fID].z ~= fz then
				knownFeatures[fID].x = fx
				knownFeatures[fID].y = fy
				knownFeatures[fID].z = fz

				knownFeatures[fID].drawAlt = ((fy > 0 and fy) or 0) + knownFeatures[fID].height + 10

				UpdateFeatureNeighborsMatrix(fID, false, true, false)
				featuresUpdated = true
			end

			if knownFeatures[fID].metal ~= metal then
				--Spring.Echo("knownFeatures[fID].metal ~= metal", metal)
				if knownFeatures[fID].clID then
					--Spring.Echo("knownFeatures[fID].clID")
					local thisCluster = featureClusters[ knownFeatures[fID].clID ]
					thisCluster.metal = thisCluster.metal - knownFeatures[fID].metal
					if metal >= minFeatureMetal then
						thisCluster.metal = thisCluster.metal + metal
						knownFeatures[fID].metal = metal
						--Spring.Echo("clusterMetalUpdated = true", thisCluster.metal)
						clusterMetalUpdated = true
					else
						UpdateFeatureNeighborsMatrix(fID, false, false, true)
						knownFeatures[fID] = nil
						featuresUpdated = true
					end
				end
			end
		end
	end
	benchmark:Leave("UpdateFeatures 1loop")

	benchmark:Enter("UpdateFeatures 2loop")
	for fID, fInfo in pairs(knownFeatures) do

		if fInfo.isGaia and Spring.ValidFeatureID(fID) == false then
			--Spring.Echo("fInfo.isGaia and Spring.ValidFeatureID(fID) == false")

			UpdateFeatureNeighborsMatrix(fID, false, false, true)
			fInfo = nil
			knownFeatures[fID] = nil
			featuresUpdated = true
		end

		if fInfo and gf - fInfo.lastScanned >= scanForRemovalInterval then --long time unseen features, maybe they were relcaimed or destroyed?
			local los = Spring.IsPosInLos(fInfo.x, fInfo.y, fInfo.z, myAllyTeamID)
			if los then --this place has no feature, it's been moved or reclaimed or destroyed
				--Spring.Echo("this place has no feature, it's been moved or reclaimed or destroyed")

				UpdateFeatureNeighborsMatrix(fID, false, false, true)
				fInfo = nil
				knownFeatures[fID] = nil
				featuresUpdated = true
			end
		end

		if fInfo and featuresUpdated then
			knownFeatures[fID].clID = nil
		end
	end
	benchmark:Leave("UpdateFeatures 2loop")
	benchmark:Leave("UpdateFeatures")
end

local Optics = VFS.Include("LuaRules/Gadgets/Include/Optics.lua")

local function ClusterizeFeatures()
	benchmark:Enter("ClusterizeFeatures")
	local pointsTable = {}

	local unclusteredPoints  = {}

	--Spring.Echo("#knownFeatures", #knownFeatures)

	for fID, fInfo in pairs(knownFeatures) do
		pointsTable[#pointsTable + 1] = {
			x = fInfo.x,
			z = fInfo.z,
			fID = fID,
		}
		unclusteredPoints[fID] = true
	end

	--TableEcho(featureNeighborsMatrix, "featureNeighborsMatrix")

	local opticsObject = Optics.new(pointsTable, featureNeighborsMatrix, minPoints, benchmark)
	benchmark:Enter("opticsObject:Run()")
	opticsObject:Run()
	benchmark:Leave("opticsObject:Run()")

	benchmark:Enter("opticsObject:Clusterize(minDistance)")
	featureClusters = opticsObject:Clusterize(minDistance)
	benchmark:Leave("opticsObject:Clusterize(minDistance)")

	--Spring.Echo("#featureClusters", #featureClusters)


	for i = 1, #featureClusters do
		local thisCluster = featureClusters[i]

		thisCluster.xmin = math.huge
		thisCluster.xmax = -math.huge
		thisCluster.zmin = math.huge
		thisCluster.zmax = -math.huge


		local metal = 0
		for j = 1, #thisCluster.members do
			local fID = thisCluster.members[j]
			local fInfo = knownFeatures[fID]

			thisCluster.xmin = math.min(thisCluster.xmin, fInfo.x)
			thisCluster.xmax = math.max(thisCluster.xmax, fInfo.x)
			thisCluster.zmin = math.min(thisCluster.zmin, fInfo.z)
			thisCluster.zmax = math.max(thisCluster.zmax, fInfo.z)

			metal = metal + fInfo.metal
			knownFeatures[fID].clID = i
			unclusteredPoints[fID] = nil
		end

		thisCluster.metal = metal
	end

	for fID, _ in pairs(unclusteredPoints) do --add Singlepoint featureClusters
		local fInfo = knownFeatures[fID]
		local thisCluster = {}

		thisCluster.members = {fID}
		thisCluster.metal = fInfo.metal

		thisCluster.xmin = fInfo.x
		thisCluster.xmax = fInfo.x
		thisCluster.zmin = fInfo.z
		thisCluster.zmax = fInfo.z

		featureClusters[#featureClusters + 1] = thisCluster
		knownFeatures[fID].clID = #featureClusters
	end

	benchmark:Leave("ClusterizeFeatures")
end

local ConvexHull = VFS.Include("LuaRules/Gadgets/Include/ConvexHull.lua")

local minDim = 100

local featureConvexHulls = {}
local function ClustersToConvexHull()
	benchmark:Enter("ClustersToConvexHull")
	featureConvexHulls = {}
	--Spring.Echo("#featureClusters", #featureClusters)
	for fc = 1, #featureClusters do
		local clusterPoints = {}
		benchmark:Enter("ClustersToConvexHull 1st Part")
		for fcm = 1, #featureClusters[fc].members do
			local fID = featureClusters[fc].members[fcm]
			clusterPoints[#clusterPoints + 1] = {
				x = knownFeatures[fID].x,
				y = knownFeatures[fID].drawAlt,
				z = knownFeatures[fID].z
			}
			--Spring.MarkerAddPoint(knownFeatures[fID].x, 0, knownFeatures[fID].z, string.format("%i(%i)", fc, fcm))
		end
		benchmark:Leave("ClustersToConvexHull 1st Part")

		--- TODO perform pruning as described in the article below, if convex hull algo will start to choke out
		-- http://mindthenerd.blogspot.ru/2012/05/fastest-convex-hull-algorithm-ever.html

		benchmark:Enter("ClustersToConvexHull 2nd Part")
		local convexHull
		if #clusterPoints >= 3 then
			--Spring.Echo("#clusterPoints >= 3")
			--convexHull = ConvexHull.JarvisMarch(clusterPoints, benchmark)
			convexHull = ConvexHull.MonotoneChain(clusterPoints, benchmark) --twice faster
		else
			--Spring.Echo("not #clusterPoints >= 3")
			local thisCluster = featureClusters[fc]

			local xmin, xmax, zmin, zmax = thisCluster.xmin, thisCluster.xmax, thisCluster.zmin, thisCluster.zmax

			local dx, dz = xmax - xmin, zmax - zmin

			if dx < minDim then
				xmin = xmin - (minDim - dx) / 2
				xmax = xmax + (minDim - dx) / 2
			end

			if dz < minDim then
				zmin = zmin - (minDim - dz) / 2
				zmax = zmax + (minDim - dz) / 2
			end

			local height = clusterPoints[1].y
			if #clusterPoints == 2 then
				height = math.max(height, clusterPoints[2].y)
			end

			convexHull = {
				{x = xmin, y = height, z = zmin},
				{x = xmax, y = height, z = zmin},
				{x = xmax, y = height, z = zmax},
				{x = xmin, y = height, z = zmax},
			}
		end

		local cx, cz, cy = 0, 0, 0
		for i = 1, #convexHull do
			local convexHullPoint = convexHull[i]
			cx = cx + convexHullPoint.x
			cz = cz + convexHullPoint.z
			cy = math.max(cy, convexHullPoint.y)
		end
		benchmark:Leave("ClustersToConvexHull 2nd Part")

		benchmark:Enter("ClustersToConvexHull 3rd Part")
		local totalArea = 0
		local pt1 = convexHull[1]
		for i = 2, #convexHull - 1 do
			local pt2 = convexHull[i]
			local pt3 = convexHull[i + 1]
			--Heron formula to get triangle area
			local a = math.sqrt((pt2.x - pt1.x)^2 + (pt2.z - pt1.z)^2)
			local b = math.sqrt((pt3.x - pt2.x)^2 + (pt3.z - pt2.z)^2)
			local c = math.sqrt((pt3.x - pt1.x)^2 + (pt3.z - pt1.z)^2)
			local p = (a + b + c)/2 --half perimeter

			local triangleArea = math.sqrt(p * (p - a) * (p - b) * (p - c))
			totalArea = totalArea + triangleArea
		end
		benchmark:Leave("ClustersToConvexHull 3rd Part")

		convexHull.area = totalArea
		convexHull.center = {x = cx/#convexHull, z = cz/#convexHull, y = cy + 1}

		featureConvexHulls[fc] = convexHull

--[[
		for i = 1, #convexHull do
			Spring.MarkerAddPoint(convexHull[i].x, convexHull[i].y, convexHull[i].z, string.format("C%i(%i)", fc, i))
		end
]]--
		benchmark:Leave("ClustersToConvexHull")
	end
end


--local reclaimColor = (1.0, 0.2, 1.0, 0.7);
local reclaimColor = {1.0, 0.2, 1.0, 0.3}
local reclaimEdgeColor = {1.0, 0.2, 1.0, 0.5}


local function ColorMul(scalar, actionColor)
	return {scalar * actionColor[1], scalar * actionColor[2], scalar * actionColor[3], actionColor[4]}
end

function widget:Initialize()
	-- This information is pretty useful as a spectator too
	-- CheckSpecState(widgetName)
	local curModID = string.upper(Game.modShortName or "")
	if ( curModID ~= "ZK" ) then
		widgetHandler:RemoveWidget()
		return
	end

	UpdateTeamAndAllyTeamID()

	--local iconDist = Spring.GetConfigInt("UnitIconDist")

	screenx, screeny = widgetHandler:GetViewSizes()

	--ToggleIdle()
end

local color
local cameraScale

local drawFeatureConvexHullSolidList
local function DrawFeatureConvexHullSolid()
	gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
	for i = 1, #featureConvexHulls do
		gl.PushMatrix()

		gl.BeginEnd(GL.TRIANGLE_FAN, function()
			for j = 1, #featureConvexHulls[i] do
				gl.Vertex(featureConvexHulls[i][j].x, featureConvexHulls[i][j].y, featureConvexHulls[i][j].z)
			end
		end)

		gl.PopMatrix()
	end
end

local drawFeatureConvexHullEdgeList
local function DrawFeatureConvexHullEdge()
	gl.PolygonMode(GL.FRONT_AND_BACK, GL.LINE)
	for i = 1, #featureConvexHulls do
		gl.PushMatrix()

		gl.BeginEnd(GL.LINE_LOOP, function()
			for j = 1, #featureConvexHulls[i] do
				gl.Vertex(featureConvexHulls[i][j].x, featureConvexHulls[i][j].y, featureConvexHulls[i][j].z)
			end
		end)

		gl.PopMatrix()
	end
	gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
end

local fontSizeMin = 40 --font size for minDim sized convex Hull
local fontSizeMax = 250

local drawFeatureClusterTextList
local function DrawFeatureClusterText()
	for i = 1, #featureConvexHulls do
		gl.PushMatrix()

		local center = featureConvexHulls[i].center

		gl.Translate(center.x, center.y, center.z)
		gl.Rotate(-90, 1, 0, 0)

		local fontSize = 25
		local area = featureConvexHulls[i].area
		fontSize = math.sqrt(area) * fontSize / minDim
		fontSize = math.max(fontSize, fontSizeMin)
		fontSize = math.min(fontSize, fontSizeMax)


		local metal = featureClusters[i].metal
		--Spring.Echo(metal)
		local metalText
		if metal < 1000 then
			metalText = string.format("%.0f", metal) --exact number
		elseif metal < 10000 then
			metalText = string.format("%.1fK", math.floor(metal / 100) / 10) --4.5K
		else
			metalText = string.format("%.0fK", math.floor(metal / 1000)) --40K
		end

		local x100  = 100  / (100  + metal)
		local x1000 = 1000 / (1000 + metal)
		local r = 1 - x1000
		local g = x1000 - x100
		local b = x100

		gl.Color(r, g, b, 1.0)
		--gl.Rect(-200, -200, 200, 200)
		gl.Text(metalText, 0, 0, fontSize, "cv")


		gl.PopMatrix()
	end
end

local checkFrequency = 30

local cumDt = 0
function widget:Update(dt)
	cumDt = cumDt + dt
	local cx, cy, cz = Spring.GetCameraPosition()

	local desc, w = Spring.TraceScreenRay(screenx / 2, screeny / 2, true)
	if desc then
		local cameraDist = math.min( 8000, math.sqrt( (cx-w[1])^2 + (cy-w[2])^2 + (cz-w[3])^2 ) )
		cameraScale = math.sqrt((cameraDist / 600)) --number is an "optimal" view distance
	else
		cameraScale = 1.0
	end

	local frame=Spring.GetGameFrame()
	color = 0.5 + 0.5 * (frame % checkFrequency - checkFrequency)/(checkFrequency - 1)
	if color < 0 then color = 0 end
	if color > 1 then color = 1 end
end

function widget:GameFrame(frame)
	local frameMod = frame % checkFrequency
	if frameMod == 0 then
		benchmark:Enter("GameFrame UpdateFeatures")
		UpdateFeatures(frame)
		--Spring.Echo("featuresUpdated", featuresUpdated)
		if featuresUpdated then
			ClusterizeFeatures()
			ClustersToConvexHull()
			--Spring.Echo("LuaUI memsize before = ", collectgarbage("count"))
			--collectgarbage("collect")
			--Spring.Echo("LuaUI memsize after = ", collectgarbage("count"))
			--benchmark:PrintAllStat()
		end

		if featuresUpdated or drawFeatureConvexHullSolidList == nil then
			benchmark:Enter("featuresUpdated or drawFeatureConvexHullSolidList == nil")
			--Spring.Echo("featuresUpdated")
			if drawFeatureConvexHullSolidList then
				gl.DeleteList(drawFeatureConvexHullSolidList)
				drawFeatureConvexHullSolidList = nil
			end

			if drawFeatureConvexHullEdgeList then
				gl.DeleteList(drawFeatureConvexHullEdgeList)
				drawFeatureConvexHullEdgeList = nil
			end


			drawFeatureConvexHullSolidList = gl.CreateList(DrawFeatureConvexHullSolid)
			drawFeatureConvexHullEdgeList = gl.CreateList(DrawFeatureConvexHullEdge)
			benchmark:Leave("featuresUpdated or drawFeatureConvexHullSolidList == nil")
		end

		if featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil then
			benchmark:Enter("featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil")
			--Spring.Echo("clusterMetalUpdated")
			if drawFeatureClusterTextList then
				gl.DeleteList(drawFeatureClusterTextList)
				drawFeatureClusterTextList = nil
			end
			drawFeatureClusterTextList = gl.CreateList(DrawFeatureClusterText)
			benchmark:Leave("featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil")
		end
		benchmark:Leave("GameFrame UpdateFeatures")
	end
end

function widget:ViewResize(viewSizeX, viewSizeY)
	screenx, screeny = widgetHandler:GetViewSizes()
end

function widget:DrawWorld()
	if Spring.IsGUIHidden() then return end
	gl.DepthTest(false)
	--gl.DepthTest(true)

	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	if drawFeatureConvexHullSolidList then
		gl.Color(ColorMul(color, reclaimColor))
		gl.CallList(drawFeatureConvexHullSolidList)
		--DrawFeatureConvexHullSolid()
	end

	if drawFeatureConvexHullEdgeList then
		gl.LineWidth(6.0 / cameraScale)
		gl.Color(ColorMul(color, reclaimEdgeColor))
		gl.CallList(drawFeatureConvexHullEdgeList)
		--DrawFeatureConvexHullEdge()
		gl.LineWidth(1.0)
	end


	if drawFeatureClusterTextList then
		gl.CallList(drawFeatureClusterTextList)
		--DrawFeatureClusterText()
	end

	gl.DepthTest(true)

end

function widget:Shutdown()
	if drawFeatureConvexHullSolidList then
		gl.DeleteList(drawFeatureConvexHullSolidList)
	end
	if drawFeatureConvexHullEdgeList then
		gl.DeleteList(drawFeatureConvexHullEdgeList)
	end
	if drawFeatureClusterTextList then
		gl.DeleteList(drawFeatureClusterTextList)
	end
	benchmark:PrintAllStat()
end