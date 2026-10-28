-- 3D preview toggle for Transport Fever 3.
--
-- The live camera preview at the top of a vehicle window is a
-- builtin.EntityRendererComponent (base gui/entity_window/vehicle/vehicle.tl).
-- On Linux/Vulkan an open preview roughly halves the frame rate (GPU load drops
-- from ~99% to ~70%, looks like a per-frame CPU<->GPU sync stall). This mod
-- wraps builtin.EntityRendererComponent: for vehicles, persons and landmarks
-- (base gui/entity_window/perk/perk.tl, also used for company headquarters)
-- it returns an empty placeholder while the preview is switched off, so no
-- preview camera is created at all. A checkbox plugin in these windows toggles
-- the state for all of them at once. In vehicle windows the overlay widgets
-- stay visible as a thin strip: top-anchored ones (specialisations, modifiers
-- such as -20 % pollution) in a first row, bottom-anchored ones (cockpit
-- button, speed) in a second row below, so they no longer overlap the way they
-- would in one zero-height FloatingLayout. The landmark window has no overlays,
-- the preview simply disappears there.
--
-- The preview sits in a FloatingLayout together with overlay widgets (cockpit
-- button, speed, specialisation icons). Swapping only the preview node left
-- that layout with stale geometry when the preview came back, so the wrappers
-- below also tag the FloatingLayoutChild holding the preview and give the
-- enclosing FloatingLayout a localKey that changes with the toggle state. A
-- changed localKey makes react recreate the layout node, i.e. fresh geometry.
-- While the preview is off, the FloatingLayoutChild calls after the preview's
-- child are only recorded (not created) and the FloatingLayout wrapper creates
-- them in the two rows instead, so no node is created and then dropped.
--
-- Loaded via react-plugin resources (entry.res.lua, toggle.res.lua), so this
-- runs inside the game's GUI Lua state. builtin.lua is cached per resolved
-- path, so the wrappers affect base vehicle.tl as well.
-- .script.lua files must export via function data().

function data()
	local VERSION = "0.6.0"

	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"

	local EVENT = "kampfmoehre_preview_toggle_changed"
	local LABEL_KEY = "3D preview" -- translated via strings.json

	-- Shared on/off state for all toggled windows (session only).
	local previewEnabled = true

	-- Node ids from the current render pass, used to find the preview's layout.
	local lastPreviewNode = nil
	local lastPreviewChild = nil

	-- Builtins may be called as builtin.X{params} or builtin.X(react.ref(r), {params})
	-- (see react.lua splitParams); the params table is always the last argument.
	local function lastArg(...)
		local n = select("#", ...)
		if n == 0 then return nil end
		return (select(n, ...))
	end

	-- Recipe id of the landmark window content, resolved on first use. The
	-- landmark preview is not tied to a component we could check cheaply, so it
	-- is recognised by the recipe that calls the renderer.
	local perkRecipeId = nil
	local function isPerkWindow()
		if perkRecipeId == nil then
			local ok, recipe = pcall(ug_require, "::/gui/entity_window/perk/perk.tl")
			perkRecipeId = ok and react.GetRecipeId(recipe) or false
		end
		return perkRecipeId ~= false and react.getCurrentRecipeId() == perkRecipeId
	end

	-- Windows whose preview is toggled: transport vehicles, persons (whose
	-- window shows their private car while they drive) and landmarks.
	local function isToggled(entity)
		if entity == nil then
			return false
		end
		if isPerkWindow() then return true end
		local ok, tv = pcall(api.engine.getComponent, entity, api.type.ComponentType.TRANSPORT_VEHICLE)
		if ok and tv ~= nil then return true end
		local okP, sp = pcall(api.engine.getComponent, entity, api.type.ComponentType.SIM_PERSON)
		return okP and sp ~= nil
	end

	if not builtin._kampfmoehrePreviewToggleOrig then
		local origRenderer = builtin.EntityRendererComponent
		local origChild = builtin.FloatingLayoutChild
		local origLayout = builtin.FloatingLayout
		builtin._kampfmoehrePreviewToggleOrig = origRenderer

		builtin.EntityRendererComponent = function(...)
			local params = lastArg(...)
			if type(params) == "table" and isToggled(params.entity) then
				-- We are inside the hosting recipe (vehicle.tl, perk.tl) here, so react hooks
				-- are legal and run once per render in a stable order: a state to
				-- re-render the host when the toggle changes, and the event hook.
				local state = react.useState(previewEnabled)
				react.onEvent(EVENT, function()
					state:set(previewEnabled)
				end)

				local node
				if previewEnabled then
					node = origRenderer(...)
				else
					node = builtin.Component{
						meta = { class = "satan-preview-off" },
						layout = builtin.BoxLayout{ children = {} },
					}
				end
				lastPreviewNode = node
				return node
			end
			return origRenderer(...)
		end

		-- Overlay children recorded while the preview is off (see header).
		local pendingMarker = {}
		local collecting = false

		local function isPending(child)
			return type(child) == "table" and child[pendingMarker] ~= nil
		end

		local function createPending(child)
			local args = child[pendingMarker]
			return origChild((table.unpack or unpack)(args, 1, args.n))
		end

		builtin.FloatingLayoutChild = function(...)
			local params = lastArg(...)
			if type(params) == "table" and lastPreviewNode ~= nil and params.item == lastPreviewNode then
				local node = origChild(...)
				lastPreviewChild = node
				lastPreviewNode = nil
				collecting = not previewEnabled
				return node
			end
			if collecting and type(params) == "table" then
				return { [pendingMarker] = { n = select("#", ...), ... } }
			end
			return origChild(...)
		end

		builtin.FloatingLayout = function(...)
			local params = lastArg(...)
			if type(params) ~= "table" or type(params.children) ~= "table" then
				return origLayout(...)
			end
			local hasPreview = false
			for __, child in ipairs(params.children) do
				if child == lastPreviewChild then
					hasPreview = true
					break
				end
			end
			if not hasPreview then
				-- Not the preview's layout (e.g. one nested in an overlay item):
				-- create any recorded children in place.
				for i, child in ipairs(params.children) do
					if isPending(child) then
						params.children[i] = createPending(child)
					end
				end
				return origLayout(...)
			end

			lastPreviewChild = nil
			collecting = false
			local meta = params.meta or {}
			meta.localKey = previewEnabled and "satan-preview-on" or "satan-preview-off"
			params.meta = meta
			if previewEnabled then
				return origLayout(...)
			end

			-- Preview off: bottom-anchored overlays (v == 1) get their own row
			-- below the rest.
			local top, bottom = {}, {}
			for __, child in ipairs(params.children) do
				if isPending(child) then
					local childParams = lastArg((table.unpack or unpack)(child[pendingMarker], 1, child[pendingMarker].n))
					local row = (type(childParams) == "table" and childParams.v == 1) and bottom or top
					row[#row + 1] = createPending(child)
				else
					top[#top + 1] = child
				end
			end
			local rows = {
				origLayout{ meta = { class = "kampfmoehre-preview-strip" }, children = top },
			}
			if #bottom > 0 then
				rows[#rows + 1] = origLayout{ meta = { class = "kampfmoehre-preview-strip" }, children = bottom }
			end
			return builtin.BoxLayout{
				meta = { class = "kampfmoehre-preview-strip", localKey = meta.localKey },
				orientation = builtin.type.Orientation.Vertical,
				children = rows,
			}
		end

		log.message("[kampfmoehre_preview_toggle] v" .. VERSION .. " builtin wrappers installed")
	end

	local preview_toggle = {}

	-- Initial state from the mod parameter chosen when loading the game
	-- (mod.json "previewDefault", Button Off/On). Values from
	-- api.engine.config.getModParams() are 1-based: 1 = Off, 2 = On.
	local function applyModParams()
		local ok, all = pcall(api.engine.config.getModParams)
		if not ok or type(all) ~= "table" then
			return
		end
		local mine = all["kampfmoehre_preview_toggle_1"]
		if type(mine) == "table" and mine.previewDefault ~= nil then
			previewEnabled = (mine.previewDefault == 2)
			log.message("[kampfmoehre_preview_toggle] default from mod params: preview " .. (previewEnabled and "on" or "off"))
		end
	end

	-- Keeps the script loaded from game start (ModEntryPointExtension) and
	-- applies the configured default once per loaded game.
	preview_toggle.EntryPlugin = react.RegisterPluginRecipe(
		{ id = "::ModEntryPointExtension" }, "KampfmoehrePreviewToggleEntry",
		function()
			react.onMount(function()
				applyModParams()
			end)
			return builtin.BoxLayout{ children = {} }
		end)

	-- Checkbox row shown in every vehicle, person and landmark window.
	-- RegisterPluginRecipe only needs the extension point's id (and no
	-- wrappedRecipe); discovery happens through the resource type string.
	local function togglePluginFn(_params)
			-- Re-render this row when the toggle changes in ANY window, and
			-- drive the checkbox from the shared state (controlled "value"), so all
			-- open windows show the same state.
			local state = react.useState(previewEnabled)
			react.onEvent(EVENT, function()
				state:set(previewEnabled)
			end)

			local children = {
				builtin.CheckBox{
					label = _(LABEL_KEY),
					value = previewEnabled and 1 or 0,
					onValueChange = function(value)
						previewEnabled = (value == 1)
						log.message("[kampfmoehre_preview_toggle] preview " .. (previewEnabled and "on" or "off"))
						api.gui.fireReactEvent(EVENT, {})
					end,
				},
			}
			return builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = children,
			}
	end

	preview_toggle.TogglePlugin = react.RegisterPluginRecipe(
		{ id = "::VehicleEowExtensionPoint" }, "KampfmoehrePreviewTogglePlugin", togglePluginFn)
	preview_toggle.PersonTogglePlugin = react.RegisterPluginRecipe(
		{ id = "::SimPersonEowExtensionPoint" }, "KampfmoehrePreviewTogglePersonPlugin", togglePluginFn)
	preview_toggle.PerkTogglePlugin = react.RegisterPluginRecipe(
		{ id = "::PerkEowExtensionPoint" }, "KampfmoehrePreviewTogglePerkPlugin", togglePluginFn)

	return preview_toggle
end
