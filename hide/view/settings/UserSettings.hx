package hide.view.settings;

class UserSettings extends Settings {
	public function new( ?state ) {
		super(state);

		var ide = Ide.inst;

		var general = new hide.view.settings.Settings.Categorie("General");
		general.add("Auto-save prefabs before closing", new Element('<input type="checkbox"/>'), ide.ideConfig.autoSavePrefab, (v) -> ide.ideConfig.autoSavePrefab = v);
		general.add("Use alternate font", new Element('<input type="checkbox"/>'), ide.ideConfig.useAlternateFont, (v) -> {ide.ideConfig.useAlternateFont = v; ide.refreshFont();});
		general.add("Show versioned files in filetree", new Element('<input type="checkbox"/>'), ide.ideConfig.svnShowVersionedFiles, (v) -> {ide.ideConfig.svnShowVersionedFiles = v; for(view in ide.getViews(FileBrowser)) view.refreshVCS(); });
		general.add("Show modified files in filetree", new Element('<input type="checkbox"/>'), ide.ideConfig.svnShowModifiedFiles, (v) -> {ide.ideConfig.svnShowModifiedFiles = v; for(view in ide.getViews(FileBrowser)) view.refreshVCS(); });
		general.add("Screen capture resolution", new Element('<input type="number"/>'), ide.ideConfig.screenCaptureResolution, (v) -> {ide.ideConfig.screenCaptureResolution = v; });
		general.add("Minimal distance from camera on drag", new Element('<input type="number"/>'), ide.ideConfig.minDistFromCameraOnDrag, (v) -> {ide.ideConfig.minDistFromCameraOnDrag = v; });

		categories.push(general);

		var search = new hide.view.settings.Settings.Categorie("Search");
		search.add("Typing debounce threshold (ms)", new Element('<input type="number"/>'), ide.ideConfig.typingDebounceThreshold, (v) -> ide.ideConfig.typingDebounceThreshold = v);
		search.add("Close search on file opening", new Element('<input type="checkbox"/>'), ide.ideConfig.closeSearchOnFileOpen, (v) -> ide.ideConfig.closeSearchOnFileOpen = v);
		search.add("Close search on CDB Sheet change", new Element('<input type="checkbox"/>'), ide.ideConfig.closeSearchOnCDBSheetChange, (v) -> ide.ideConfig.closeSearchOnCDBSheetChange = v);

		categories.push(search);

		var performance = new hide.view.settings.Settings.Categorie("Performance");
		performance.add("Track gpu alloc", new Element('<input type="checkbox"/>'), ide.ideConfig.trackGpuAlloc, (v) -> ide.ideConfig.trackGpuAlloc = v);
		performance.add("Slow scene update when not focused", new Element('<input type="checkbox"/>'), ide.ideConfig.unfocusCPUSavingMode, (v) -> ide.ideConfig.unfocusCPUSavingMode = v);
		categories.push(performance);

		var sceneEditor = new hide.view.settings.Settings.Categorie("Scene Editor");
		sceneEditor.add("Use objects collision on drag", new Element('<input type="checkbox"/>'), ide.ideConfig.collisionOnDrag, (v) -> {ide.ideConfig.collisionOnDrag = v; });
		sceneEditor.add("Orient mesh on drag", new Element('<input type="checkbox"/>'), ide.ideConfig.orientMeshOnDrag, (v) -> {ide.ideConfig.orientMeshOnDrag = v; });
		sceneEditor.add("Click cycle objects under the mouse", new Element('<input type="checkbox"/>'), ide.ideConfig.sceneEditorClickCycleObjects, (v) -> ide.ideConfig.sceneEditorClickCycleObjects = v);
		categories.push(sceneEditor);

		var cdb = new hide.view.settings.Settings.Categorie("CDB");
		cdb.add("Search on key press", new Element('<input type="checkbox"/>'), ide.ideConfig.searchOnKeyPress, (v) -> ide.ideConfig.searchOnKeyPress = v);
		cdb.add("Highlight active line", new Element('<input type="checkbox"/>'), ide.ideConfig.highlightActiveLine, (v) -> ide.ideConfig.highlightActiveLine = v);
		cdb.add("Highlight active line header", new Element('<input type="checkbox"/>'), ide.ideConfig.highlightActiveLineHeader, (v) -> ide.ideConfig.highlightActiveLineHeader = v);
		cdb.add("Highlight active column header", new Element('<input type="checkbox"/>'), ide.ideConfig.highlightActiveColumnHeader, (v) -> ide.ideConfig.highlightActiveColumnHeader = v);
		categories.push(cdb);

		var debug = new hide.view.settings.Settings.Categorie("Debug");
		debug.add("Filebrowser ignore thumbnail cache", new Element('<input type="checkbox"/>'), ide.ideConfig.filebrowserDebugIgnoreThumbnailCache, (v) -> ide.ideConfig.filebrowserDebugIgnoreThumbnailCache = v);
		debug.add("Filebrowser print server logs", new Element('<input type="checkbox"/>'), ide.ideConfig.filebrowserDebugServerCommands, (v) -> ide.ideConfig.filebrowserDebugServerCommands = v);
		debug.add("Filebrowser show thumbnail gen window", new Element('<input type="checkbox"/>'), ide.ideConfig.filebrowserDebugShowWindow, (v) -> ide.ideConfig.filebrowserDebugShowWindow = v);
		debug.add("Filebrowser show debug menu", new Element('<input type="checkbox"/>'), ide.ideConfig.filebrowserDebugShowMenu, (v) -> ide.ideConfig.filebrowserDebugShowMenu = v);
		categories.push(debug);
	}

	override function getTitle() {
		return "User Settings";
	}

	static var _ = hide.ui.View.register(UserSettings);
}
