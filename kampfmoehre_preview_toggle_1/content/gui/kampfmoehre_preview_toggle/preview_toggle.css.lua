local ssu = require "::/gui/main/stylesheetutil.lua"

-- Overlay rows that replace the preview's FloatingLayout while the preview is
-- off (see preview_toggle.script.lua): full window width, so right-anchored
-- overlays (speed) stay at the right edge.
function data()
	local result = {}
	local a = ssu.makeAdder(result)

	a("R::EntityWindowContent !kampfmoehre-preview-strip", {
		gravity = { -1, 0 },
	})

	return result
end
