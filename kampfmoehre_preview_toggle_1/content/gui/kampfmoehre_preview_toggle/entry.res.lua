-- Loads the script early (before any vehicle window exists) so the
-- EntityRendererComponent wrapper is in place from the start.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "kampfmoehre_preview_toggle_1::/gui/kampfmoehre_preview_toggle/preview_toggle.script@EntryPlugin",
			order = 0,
		}
	}
end
