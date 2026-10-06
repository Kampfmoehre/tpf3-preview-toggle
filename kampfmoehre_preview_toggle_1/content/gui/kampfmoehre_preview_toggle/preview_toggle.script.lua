-- Vehicle 3D preview toggle for Transport Fever 3.
--
-- The live camera preview at the top of a vehicle window is a
-- builtin.EntityRendererComponent (base gui/entity_window/vehicle/vehicle.tl).
-- On Linux/Vulkan an open preview roughly halves the frame rate (GPU load drops
-- from ~99% to ~70%, looks like a per-frame CPU<->GPU sync stall). This mod
-- wraps builtin.EntityRendererComponent: for vehicles it returns an empty
-- placeholder while the preview is switched off, so no preview camera is
-- created at all. A checkbox plugin in the vehicle window toggles the state
-- for all vehicle windows at once. The overlay widgets (cockpit button, speed)
-- stay visible as a thin strip above the placeholder.
--
-- The preview sits in a FloatingLayout together with overlay widgets (cockpit
-- button, speed, specialisation icons). Swapping only the preview node left
-- that layout with stale geometry when the preview came back, so the wrappers
-- below also tag the FloatingLayoutChild holding the preview and give the
-- enclosing FloatingLayout a localKey that changes with the toggle state. A
-- changed localKey makes react recreate the layout node, i.e. fresh geometry.
--
-- Loaded via react-plugin resources (entry.res.lua, toggle.res.lua), so this
-- runs inside the game's GUI Lua state. builtin.lua is cached per resolved
-- path, so the wrappers affect base vehicle.tl as well.
-- .script.lua files must export via function data().

function data()
	local VERSION = "0.4.0"

	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"

	local EVENT = "kampfmoehre_preview_toggle_changed"
	local LABEL_KEY = "3D preview" -- translated via strings.json

	-- Shared on/off state for all vehicle windows (session only).
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

	-- Windows whose preview is toggled: transport vehicles and persons (whose
	-- window shows their private car while they drive).
	local function isVehicle(entity)
		if entity == nil then
			return false
		end
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
			if type(params) == "table" and isVehicle(params.entity) then
				-- We are inside the hosting recipe (vehicle.tl) here, so react hooks
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

		builtin.FloatingLayoutChild = function(...)
			local params = lastArg(...)
			local node = origChild(...)
			if type(params) == "table" and lastPreviewNode ~= nil and params.item == lastPreviewNode then
				lastPreviewChild = node
				lastPreviewNode = nil
			end
			return node
		end

		builtin.FloatingLayout = function(...)
			local params = lastArg(...)
			if type(params) == "table" and lastPreviewChild ~= nil and type(params.children) == "table" then
				for _, child in ipairs(params.children) do
					if child == lastPreviewChild then
						lastPreviewChild = nil
						local meta = params.meta or {}
						meta.localKey = previewEnabled and "satan-preview-on" or "satan-preview-off"
						params.meta = meta
						break
					end
				end
			end
			return origLayout(...)
		end

		log.message("[preview_toggle] v" .. VERSION .. " builtin wrappers installed")
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
			log.message("[preview_toggle] default from mod params: preview " .. (previewEnabled and "on" or "off"))
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

	-- Checkbox row shown in every vehicle window (VehicleEowExtensionPoint).
	-- RegisterPluginRecipe only needs the extension point's id (and no
	-- wrappedRecipe); discovery happens through the resource type string.
	local function togglePluginFn(_params)
			-- Re-render this row when the toggle changes in ANY vehicle window, and
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
						log.message("[preview_toggle] preview " .. (previewEnabled and "on" or "off"))
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

	return preview_toggle
end
