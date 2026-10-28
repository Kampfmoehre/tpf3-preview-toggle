-- Adds the checkbox widget to every landmark (and headquarters) window
-- (between the notification widget at order 0 and the basics card at order 10).
function data()
	return {
		type = "react-plugin ::PerkEowExtensionPoint",
		data = {
			filePath = "kampfmoehre_preview_toggle_1::/gui/kampfmoehre_preview_toggle/preview_toggle.script@PerkTogglePlugin",
			order = 5,
		}
	}
end
