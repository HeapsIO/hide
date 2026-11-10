package hide.view.settings;

class UserSettings extends Settings {
	public function new( ?state ) {
		super(state);

		var ide = Ide.inst;

		var general = new hide.view.settings.Settings.Categorie("General");
		general.add("Auto-save prefabs before closing", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.autoSavePrefab"), (v) -> ide.userConfig.set("hide.autoSavePrefab", v));
		general.add("Use alternate font", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.useAlternateFont"), (v) -> {ide.userConfig.set("hide.useAlternateFont", v); ide.refreshFont();});
		general.add("Show versioned files in filetree", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.svnShowVersionedFiles"), (v) -> {ide.userConfig.set("hide.svnShowVersionedFiles", v); for(view in ide.getViews(FileBrowser)) view.refreshVCS(); });
		general.add("Show modified files in filetree", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.svnShowModifiedFiles"), (v) -> {ide.userConfig.set("hide.svnShowModifiedFiles", v); for(view in ide.getViews(FileBrowser)) view.refreshVCS(); });
		general.add("Screen capture resolution", new Element('<input type="number"/>'), ide.currentConfig.get("hide.screenCaptureResolution"), (v) -> {ide.userConfig.set("hide.screenCaptureResolution", v); });
		general.add("Minimal distance from camera on drag", new Element('<input type="number"/>'), ide.currentConfig.get("hide.minDistFromCameraOnDrag"), (v) -> {ide.userConfig.set("hide.minDistFromCameraOnDrag", v); });
		general.add("ESC on Color Picker undo changes", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.colorPickerEscUndo"), (v) -> ide.userConfig.set("hide.colorPickerEscUndo", v));


		categories.push(general);

		var search = new hide.view.settings.Settings.Categorie("Search");
		search.add("Typing debounce threshold (ms)", new Element('<input type="number"/>'), ide.currentConfig.get("hide.typingDebounceThreshold"), (v) -> ide.userConfig.set("hide.typingDebounceThreshold", v));
		search.add("Close search on file opening", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.closeSearchOnFileOpen"), (v) -> ide.userConfig.set("hide.closeSearchOnFileOpen", v));
		search.add("Close search on CDB Sheet change", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.closeSearchOnCDBSheetChange"), (v) -> ide.userConfig.set("hide.closeSearchOnCDBSheetChange", v));

		categories.push(search);

		var performance = new hide.view.settings.Settings.Categorie("Performance");
		performance.add("Track gpu alloc", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.trackGpuAlloc"), (v) -> ide.userConfig.set("hide.trackGpuAlloc", v));
		performance.add("Slow scene update when not focused", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.unfocusCPUSavingMode"), (v) -> ide.userConfig.set("hide.unfocusCPUSavingMode", v));
		performance.add("Texture streaming", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.textureStreaming"), (v) -> { ide.userConfig.set("hide.textureStreaming", v); hxd.res.TextureStream.ENABLED = v; });
		categories.push(performance);

		var sceneEditor = new hide.view.settings.Settings.Categorie("Scene Editor");
		sceneEditor.add("Use objects collision on drag", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.collisionOnDrag"), (v) -> {ide.userConfig.set("hide.collisionOnDrag", v); });
		sceneEditor.add("Orient mesh on drag", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.orientMeshOnDrag"), (v) -> {ide.userConfig.set("hide.orientMeshOnDrag", v); });
		sceneEditor.add("Click cycle objects under the mouse", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.sceneEditorClickCycleObjects"), (v) -> ide.userConfig.set("hide.sceneEditorClickCycleObjects", v));
		categories.push(sceneEditor);

		var cdb = new hide.view.settings.Settings.Categorie("CDB");
		cdb.add("Search on key press", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.searchOnKeyPress"), (v) -> ide.userConfig.set("hide.searchOnKeyPress", v));
		cdb.add("Highlight active line", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.highlightActiveLine"), (v) -> ide.userConfig.set("hide.highlightActiveLine", v));
		cdb.add("Highlight active line header", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.highlightActiveLineHeader"), (v) -> ide.userConfig.set("hide.highlightActiveLineHeader", v));
		cdb.add("Highlight active column header", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.highlightActiveColumnHeader"), (v) -> ide.userConfig.set("hide.highlightActiveColumnHeader", v));
		categories.push(cdb);

		var debug = new hide.view.settings.Settings.Categorie("Debug");
		debug.add("Filebrowser ignore thumbnail cache", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.filebrowserDebugIgnoreThumbnailCache"), (v) -> ide.userConfig.set("hide.filebrowserDebugIgnoreThumbnailCache", v));
		debug.add("Filebrowser print server logs", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.filebrowserDebugServerCommands"), (v) -> ide.userConfig.set("hide.filebrowserDebugServerCommands", v));
		debug.add("Filebrowser show thumbnail gen window", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.filebrowserDebugShowWindow"), (v) -> ide.userConfig.set("hide.filebrowserDebugShowWindow", v));
		debug.add("Filebrowser show debug menu", new Element('<input type="checkbox"/>'), ide.currentConfig.get("hide.filebrowserDebugShowMenu"), (v) -> ide.userConfig.set("hide.filebrowserDebugShowMenu", v));
		categories.push(debug);
	}

	override function getTitle() {
		return "User Settings";
	}

	static var _ = hide.ui.View.register(UserSettings);
}
