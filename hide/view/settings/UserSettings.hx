package hide.view.settings;

class UserSettings extends Settings {
	public function new( ?state ) {
		super(state);

		var general = new hide.view.settings.Settings.Categorie("General");
		general.add("Auto-save prefabs before closing", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.autoSavePrefab, (v) -> Ide.inst.ideConfig.autoSavePrefab = v);
		general.add("Use alternate font", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.useAlternateFont, (v) -> {Ide.inst.ideConfig.useAlternateFont = v; Ide.inst.refreshFont();});
		general.add("Show versioned files in filetree", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.svnShowVersionedFiles, (v) -> {Ide.inst.ideConfig.svnShowVersionedFiles = v; for(view in Ide.inst.getViews(FileBrowser)) view.refreshVCS(); });
		general.add("Show modified files in filetree", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.svnShowModifiedFiles, (v) -> {Ide.inst.ideConfig.svnShowModifiedFiles = v; for(view in Ide.inst.getViews(FileBrowser)) view.refreshVCS(); });

		categories.push(general);

		var search = new hide.view.settings.Settings.Categorie("Search");
		search.add("Typing debounce threshold (ms)", new Element('<input type="number"/>'), Ide.inst.ideConfig.typingDebounceThreshold, (v) -> Ide.inst.ideConfig.typingDebounceThreshold = v);
		search.add("Close search on file opening", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.closeSearchOnFileOpen, (v) -> Ide.inst.ideConfig.closeSearchOnFileOpen = v);
		categories.push(search);

		var performance = new hide.view.settings.Settings.Categorie("Performance");
		performance.add("Track gpu alloc", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.trackGpuAlloc, (v) -> Ide.inst.ideConfig.trackGpuAlloc = v);
		performance.add("Slow scene update when not focused", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.unfocusCPUSavingMode, (v) -> Ide.inst.ideConfig.unfocusCPUSavingMode = v);
		categories.push(performance);

		var cdb = new hide.view.settings.Settings.Categorie("CDB");
		cdb.add("Highlight active line", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.highlightActiveLine, (v) -> Ide.inst.ideConfig.highlightActiveLine = v);
		cdb.add("Highlight active line header", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.highlightActiveLineHeader, (v) -> Ide.inst.ideConfig.highlightActiveLineHeader = v);
		cdb.add("Highlight active column header", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.highlightActiveColumnHeader, (v) -> Ide.inst.ideConfig.highlightActiveColumnHeader = v);
		categories.push(cdb);


		var debug = new hide.view.settings.Settings.Categorie("Debug");
		debug.add("Filebrowser ignore thumbnail cache", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.filebrowserDebugIgnoreThumbnailCache, (v) -> Ide.inst.ideConfig.filebrowserDebugIgnoreThumbnailCache = v);
		debug.add("Filebrowser show thumbnail gen window", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.filebrowserDebugShowWindow, (v) -> Ide.inst.ideConfig.filebrowserDebugShowWindow = v);
		debug.add("Filebrowser show debug menu", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.filebrowserDebugShowMenu, (v) -> Ide.inst.ideConfig.filebrowserDebugShowMenu = v);
		categories.push(debug);


	}

	override function getTitle() {
		return "User Settings";
	}

	static var _ = hide.ui.View.register(UserSettings);
}
