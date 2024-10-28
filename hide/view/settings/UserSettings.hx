package hide.view.settings;

class UserSettings extends Settings {
	public function new( ?state ) {
		super(state);

		var general = new hide.view.settings.Settings.Categorie("General");
		general.add("Auto-save prefabs before closing", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.autoSavePrefab, (v) -> Ide.inst.ideConfig.autoSavePrefab = v);
		categories.push(general);

		var search = new hide.view.settings.Settings.Categorie("Search");
		search.add("Typing debounce threshold (ms)", new Element('<input type="number"/>'), Ide.inst.ideConfig.typingDebounceThreshold, (v) -> Ide.inst.ideConfig.typingDebounceThreshold = v);
		search.add("Close search on file opening", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.closeSearchOnFileOpen, (v) -> Ide.inst.ideConfig.closeSearchOnFileOpen = v);
		categories.push(search);

		var performance = new hide.view.settings.Settings.Categorie("Performance");
		performance.add("Track gpu alloc", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.trackGpuAlloc, (v) -> Ide.inst.ideConfig.trackGpuAlloc = v);
		performance.add("Culling distance factor", new Element('<input type="number"/>'), Ide.inst.ideConfig.cullingDistanceFactor, (v) -> Ide.inst.ideConfig.cullingDistanceFactor = v);
		categories.push(performance);
	}

	override function getTitle() {
		return "User Settings";
	}

	static var _ = hide.ui.View.register(UserSettings);
}
