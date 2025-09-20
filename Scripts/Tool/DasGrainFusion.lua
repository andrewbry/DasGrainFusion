-- Adaptation of DasGrain for Fusion Studio
-- A regraining gizmo for nuke
-- Originally created by Fabian Holtz https://www.nukepedia.com/gizmos/other/dasgrain
-- Progress bar from https://www.steakunderwater.com/wesuckless/viewtopic.php?t=5095
-- Adapted for Fusion by Andrew Buckley 
-- v0.80

-------progress bar
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local weight = 350
local height = 60
-------change Progress Bar color
local pbarColor = "#FFCCAA"
-------change Progress Bar Weight
local pbarWeight = 350
-------comp info
local comp = fusion.CurrentComp
local compattrs = comp:GetAttrs()
local from = compattrs.COMPN_RenderStart
local to = compattrs.COMPN_RenderEnd
local currentf = compattrs.COMPN_CurrentTime
-------get self
local macro = self:GetTool()

-------------------
-- UI --
-------------------

if self.ID == "ABtn" then
	win = disp:AddWindow({
		ID = 'MainWin',
		WindowTitle = 'Progress Bar',
		Geometry = {1000, 500, weight, height},
		BackgroundColorl = {R = 0.125, G = 0.125, B = 0.125, A = 1},
	
		ui:VGroup{
			ID = 'root',
			MinimumSize = {weight , height},
			MaximumSize = {weight , height},
			ui:HGroup{
				ui:Label{ID = "framerange", Text = "Frames " .. macro["FRangeIn"][1] .. "-" .. macro["FRangeOut"][1], Alignment = {AlignHCenter = true,}, Weight = 1,},
			},
			ui:HGroup{
				ui:Label{ID = "description", Text = "...", Alignment = {AlignLeft = true,}, Weight = 0.9,},
				ui:Label{ID = "infolabel", Text = "", Alignment = {AlignRight = true,}, Weight = 0.1,},
			},
			ui:HGroup{
				ui:TextEdit{ID = "progressbar", ReadOnly = true, HTML = '<body bgcolor="' .. pbarColor .. '">', MaximumSize = {1, 27}, MinimumSize = {1, 27},Hidden = false, Weight = 1, Alignment = {AlignHCenter = true,},},
			},
		},
	})
else
	win = disp:AddWindow({
		ID = 'MainWin',
	})
end

function ProgressBar(v, n)
    itm.progressbar.MaximumSize = {v, 27}
    itm.progressbar.MinimumSize = {v, 27}
	itm.infolabel.Text = string.format(n)
end
 
function win.On.MainWin.Close(ev)
    disp:ExitLoop()
end

-------------------
-- end UI --
-------------------

function tableContainsValue(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function splitString(inputstr, sep)
   -- if sep is null, set it as space
   if sep == nil then
      sep = '%s'
   end
   -- define an array
   local t={}
   -- split string based on sep   
   for str in string.gmatch(inputstr, '([^'..sep..']+)') 
   do
      -- insert the substring in table
      table.insert(t, str)
   end
   -- return the array
   return t
end

function getTool(name, m)
    for i,t in pairs(m:GetChildrenList()) do
        if string.match(t.Name, name) then
            return t
        end
    end
    return
end

function allConnected(m)
	if m:FindMainInput(2):GetAttrs().INPB_Connected == true and m:FindMainInput(3):GetAttrs().INPB_Connected == true then
		return true
	else
		return false
	end
end

function generateFrameList(fc,addf)
    local frame_list = {}
    if fc > 0 then
        local distance = (macro["FRangeOut"][1] - macro["FRangeIn"][1] ) / fc
        local frame = macro["FRangeIn"][1] + distance / 2
		
        for i=1,fc do
			-- only add if not in list
			if tableContainsValue(frame_list, math.floor(frame+0.5)) == false then
				frame_list[i] = math.floor(frame+0.5) 
			end            
            frame = frame + distance
        end
    end

	for _, f in pairs(addf) do
		f = tonumber(f)
		if f >= macro["FRangeIn"][1] and f <= macro["FRangeOut"][1] then
			if not tableContainsValue(frame_list, f) then
				table.insert(frame_list, f)
			end
		end
	end

	table.sort(frame_list)
    return frame_list
end

function setFrames(t,f,retime)
    local modifier = comp:BezierSpline()
	local newtimes = {}
	local keyframes = {}

	-- delete any animation and add new modifier
	retime["SourceTime"] = nil
	retime["SourceTime"] = modifier

	-- create the keyframes
	for i=1,table.getn(f) do
		keyframes[i] = f[i]
		newtimes[i] = i
	end

	modifier:SetKeyFrames(keyframes, true)
	return newtimes
end

function getSampleRange(ch, f_lst, mm)
	local inpmin = mm["NumberIn1"]
	local inpmax = mm["NumberIn2"]
	inpmin = mm["NumberIn1"] -- twice to force update
	inpmax = mm["NumberIn2"] -- twice to force update

	local min = inpmin[1]
	local max = inpmax[1]

	for i=f_lst[1], table.getn(f_lst) do
		min = math.min(inpmin[i], min)
		max = math.max(inpmax[i], max)
	end

	print("min:" .. min .. "  max: " .. max)
	local result = {min, max}
	
	return result
end

function getSampleList(scount, srange, sradius)
    -- lerp betwen min max and get the values for the keyer slices

    sample_list = {}

	for i=1, scount do
		sample_list[i] = (i-1) / scount * (srange[2] - srange[1]) + srange[1] + sradius
	end

    return sample_list
end

function getSample(k,sampler, s, sr)
	-- set keyer value for slice
	local sample_values = {}

	-- set the keyer
	k["NumberIn1"] = s
	k["NumberIn2"] = sr

	-- get intensity data for this slice
	-- numberin1 is grain delta average luma of frames averaged at current luma slice
	-- numberin2 is denoised image average luma of frames averaged at current luma slice
	-- numberin3 is full white area averaged at current luma slice
	local sample_values = {sampler["NumberIn1"][1], sampler["NumberIn2"][1], sampler["NumberIn3"][1]}
	sample_values = {sampler["NumberIn1"][1], sampler["NumberIn2"][1], sampler["NumberIn3"][1]}

	return sample_values
end

function analyseResponse()
	local channel_list = {'Red', 'Green', 'Blue'}
	local keyer = getTool("CustomKeyer", macro)
	local set_channel = getTool("SetChannel", macro)
	local grain_sampler = getTool("GrainSample", macro)
	local minmax_sampler = getTool("MinMaxSample", macro)
	local grain_response = getTool("GrainResponse", macro)
	local retime = getTool("MultiFrameRetime", macro)
	local frameavg = getTool("BlendFrames", macro)
	local exeswitch = getTool("exe_switch", macro)
	
	local pixel = keyer:FindMainOutput(1):GetDoD()[3] * keyer:FindMainOutput(1):GetDoD()[4] 

	local sample_count = macro["NSamples"][1]
	local frame_count = macro["NFrames"][1]
	local extra_frames = splitString(macro["AddFrames"][1],nil)

	local frame_list = generateFrameList(frame_count,extra_frames)
	local retimed_frame_list = setFrames(tool, frame_list, retime)
	local listlength = 0
	local dictlength = 0
	local ch = 0
	local lutx = 0
	local luty = 0
	
	for index, channel in pairs(channel_list) do
		-- set channel and ui
		set_channel.ToRed = ch
		itm.description.Text = channel .. " Min/Max"
		-- diagnostic --
		-- exeswitch["Source"] = 2 -- set to minmax probe
		-- diagnostic --
		print(channel)
		
		-- get min max luma avarage over the amount of frames for the current channel
		local sample_range = getSampleRange(channel, retimed_frame_list, minmax_sampler)
		sample_range = getSampleRange(channel, retimed_frame_list, minmax_sampler) -- run twice to force update

		-- gets the radius needed for the sample list, radius is the values for the luma slice
		local sample_radius = (sample_range[2] - sample_range[1]) / sample_count / 2

		-- gets the sample list for each channel
		local sample_list = getSampleList(sample_count, sample_range, sample_radius)

		local lutvalues = {}
		local emptyvalues = {}
		local spline, splineout


		-- for ui progress bar
		listlength = table.getn(sample_list)
		dictlength = 0

		-- set the frame blend to average all the frames we are going to slice through
		frameavg["Frames"] = frame_count-1
		
		for key, sample in pairs(sample_list) do
			itm.description.Text = channel .. " Channel"
			ProgressBar(math.ceil((dictlength / listlength) * pbarWeight), tonumber(string.format("%.2f", sample)))
			-- diagnostic --
			-- exeswitch["Source"] = 1 -- set to keyer probe
			-- diagnostic --

			local sample_values = getSample(keyer, grain_sampler, sample, sample_radius)
			sample_values = getSample(keyer, grain_sampler, sample, sample_radius) -- run twice to force update
			
			-- create lut for channel
			if sample_values[3] * pixel >= 10 then
				lutx = sample_values[2] / sample_values[3] -- image / full white
				luty = sample_values[1] / sample_values[3] -- grain / full white 
				lutvalues[lutx] = {luty} -- grain response LUT x,y
				-- lutvalues[sample_values[2] / sample_values[3]] = {sample_values[1] / sample_values[3]}
				print("image luma:" .. sample_values[1] .. " grain luma:" .. sample_values[2] .. " 100% luma:" .. sample_values[3])
				print("x:" .. sample_values[2] / sample_values[3] .. " y:" ..sample_values[1] / sample_values[3])
			else
				print("area too small")
			end

			-- flat tangents
			if dictlength == 0 then
				lutvalues[lutx-0.1] = {luty}
			elseif key == listlength then
				lutvalues[lutx+0.1] = {luty}
			end

			dictlength = dictlength + 1
			bmd.wait(0.01)
		end
		
		emptyvalues[0] = {0}
		local lutcurve = grain_response[channel]
		-- gets the spline output that is connected to the input,
		local splineout = lutcurve:GetConnectedOutput()
		-- then uses GetTool() to get the Bezier Spline modifier itself, and
		-- Bezier LUT data [X = [Y,RH[x,x],LH[x,x]]
		if splineout then
			local spline = splineout:GetTool()
			-- bit of a wierd way to remove keys as it always seems to leave 1 at any time
			-- so I delete all before 0, add a key at 0, and delete all after 0
			-- then add our new keys and delete the one at 0
			spline:DeleteKeyFrames(-10000, 0)
    		spline:SetKeyFrames(emptyvalues, true)
    		spline:DeleteKeyFrames(0.000001, 10000)
			spline:SetKeyFrames(lutvalues, true)
			spline:DeleteKeyFrames(-0.000001, 0.000001)
		end
		ch = ch + 1	
	end

	-- diagnostic --
	-- exeswitch["Source"] = 0 -- set to main
	-- diagnostic --
	disp:ExitLoop()
	win:Hide()
end

-------------------
-- MAIN FUNCTION --
-------------------

if allConnected(macro) and self.ID == "ABtn" then
	-- check if inputs are connected in order to run successfully and run ui
	win:Show()
	itm = win:GetItems()
	itm.description.Text = "Running"
	
	disp:RunLoop(analyseResponse())
	
elseif allConnected(macro) and self.ID == "FRBtn" then
	-- we get the second inputs output tools reader frame range
	local plateinput = macro:FindMainInput(2):GetConnectedOutput():GetTool()
	macro["FRangeIn"][1] = plateinput["GlobalIn"][1]
	macro["FRangeOut"][1] = plateinput["GlobalOut"][1]

elseif self.ID == "FBtn" then
	-- set the reference frame
	macro["RefFrame"][1] = comp:GetAttrs().COMPN_CurrentTime
else
	comp:AskUser("Tool Script Error", {
		{"description", "Text", Lines=5, Default="Not all inputs are connected, can't execute.", ReadOnly=true, Wrap=true},
	})
end




 
