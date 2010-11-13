function widget:GetInfo()
  return {
    name      = "Chili Minimap",
    desc      = "v0.82 Chili Minimap",
    author    = "Licho",
    date      = "@2010",
    license   = "GNU GPL, v2 or later",
    layer     = -math.huge,
    experimental = false,
    enabled   = true --  loaded by default?
  }
end


local window_minimap
local Chili
local glDrawMiniMap = gl.DrawMiniMap
local glResetState = gl.ResetState
local glResetMatrices = gl.ResetMatrices

local iconsize = 20

local function AdjustToMapAspectRatio(w,h)
	if (Game.mapX > Game.mapY) then
		return w, w*Game.mapY/Game.mapX+iconsize
	end
	return h*Game.mapX/Game.mapY, h+iconsize
end


options_path = 'Settings/Interface'
options_order = { 'use_map_ratio', 'simplecolors', }
options = {
	
	use_map_ratio = {
		name = 'Minimap Keeps Aspect Ratio',
		type = 'bool',
		value = true,
		advanced = true,
		OnChange = function()
			if (options.use_map_ratio.value) then 
				local w,h = AdjustToMapAspectRatio(300, 200)
				window_minimap:Resize(w,h,false,false)
			end 
			window_minimap.fixedRatio = options.use_map_ratio.value;			
		end,
	},
	simplecolors = {
		name = 'Simple Radar Blip Colors',
		type = 'bool',
		desc = 'Show radar blips in the color of their team.', 
		springsetting = 'SimpleMiniMapColors',
		OnChange = function(self) Spring.SendCommands{"minimap simplecolors " .. (self.value and 1 or 0) } end,
	},
}


function widget:Initialize()
	if (Spring.GetMiniMapDualScreen()) then
		Spring.Echo("ChiliMinimap: auto disabled (DualScreen is enabled).")
		widgetHandler:RemoveWidget()
		return
	end

	if (not WG.Chili) then
		widgetHandler:RemoveWidget()
		return
	end

	Chili = WG.Chili

	local w,h = 300,200+iconsize
	if (options.use_map_ratio.value) then
		w,h = AdjustToMapAspectRatio(w,h)
	end

	window_minimap = Chili.Window:New{  
		dockable = true,
		name = "minimap",
		x = 0,  
		y = 0,
		width  = w,
		height = h,
		parent = Chili.Screen0,
		draggable = false,
		tweakDraggable = true,
		resizable = true,
		fixedRatio = options.use_map_ratio.value,
		dragUseGrip = true,
		minimumSize = {50,50},
		children = {
			Chili.Button:New{ height=iconsize, width=iconsize, caption='-', bottom=0, right=iconsize*1, tooltip='Normal View', 	OnClick={function() Spring.SendCommands{"showstandard"} 	end}, },
			Chili.Button:New{ height=iconsize, width=iconsize, caption='H', bottom=0, right=iconsize*2, tooltip='Height Map',	OnClick={function() Spring.SendCommands{"showelevation"} 	end}, },
			Chili.Button:New{ height=iconsize, width=iconsize, caption='B', bottom=0, right=iconsize*3, tooltip='Pathing Map', 	OnClick={function() Spring.SendCommands{"showpathmap"} 		end}, },
			Chili.Button:New{ height=iconsize, width=iconsize, caption='M', bottom=0, right=iconsize*4, tooltip='Metal Map', 	OnClick={function() Spring.SendCommands{"ShowMetalMap"} 	end}, },
			
			Chili.Button:New{ height=iconsize, width=iconsize, caption='L', bottom=0, right=iconsize*6, tooltip='Fog of War View', 	
								OnClick={function() Spring.SendCommands{"togglelos"} 			end}, },
			Chili.Button:New{ height=iconsize, width=iconsize, caption='R', bottom=0, right=iconsize*7, tooltip='Radar & Jammer view (Only shows when Fog of War is enabled)', 	
								OnClick={function() Spring.SendCommands{"toggleradarandjammer"} end}, },
		},
	}
	gl.SlaveMiniMap(true)
end


function widget:Shutdown()
	--// reset engine default minimap rendering
	gl.SlaveMiniMap(false)
	Spring.SendCommands("minimap geo " .. Spring.GetConfigString("MiniMapGeometry"))

	--// free the chili window
	if (window_minimap) then
		window_minimap:Dispose()
	end
end 


local lx, ly, lw, lh

function widget:DrawScreen() 
	if (lw ~= window_minimap.width or lh ~= window_minimap.height or lx ~= window_minimap.x or ly ~= window_minimap.y) then 
		local cx,cy,cw,ch = Chili.unpack4(window_minimap.clientArea)
		ch = ch-iconsize*1.2		
		cx = cx - 4
		cy = cy - 4
		cw = cw + 8
		ch = ch + 8
		--window_minimap.x, window_minimap.y, window_minimap.width, window_minimap.height
		--Chili.unpack4(window_minimap.clientArea)
		cx,cy = window_minimap:LocalToScreen(cx,cy)
		local vsx,vsy = gl.GetViewSizes()
		gl.ConfigMiniMap(cx,vsy-ch-cy,cw,ch)
		lx = window_minimap.x
		ly = window_minimap.y
		lh = window_minimap.height
		lw = window_minimap.width
	end

	gl.PushAttrib(GL.ALL_ATTRIB_BITS)
	gl.MatrixMode(GL.PROJECTION)
	gl.PushMatrix()
	gl.MatrixMode(GL.MODELVIEW)
	gl.PushMatrix()

	glDrawMiniMap()

	gl.MatrixMode(GL.PROJECTION)
	gl.PopMatrix()
	gl.MatrixMode(GL.MODELVIEW)
	gl.PopMatrix()
	gl.PopAttrib()
end 
