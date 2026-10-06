-- Adds the checkbox widget to every person window (above the locations card).
function data()
	return {
		type = "react-plugin ::SimPersonEowExtensionPoint",
		data = {
			filePath = "kampfmoehre_preview_toggle_1::/gui/kampfmoehre_preview_toggle/preview_toggle.script@PersonTogglePlugin",
			order = 10,
		}
	}
end
