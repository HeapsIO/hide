package hide.view;

class Settings extends hide.ui.View<{}> {
	public var categories : Array<Categorie>;

	public function new( ?state ) {
		super(state);

		categories = [];

		var general = new Categorie("General");
		general.add("Auto-save prefabs before closing", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.autoSavePrefab, (v) -> Ide.inst.ideConfig.autoSavePrefab = v);
		categories.push(general);

		var search = new Categorie("Search");
		search.add("Typing debounce threshold (ms)", new Element('<input type="number"/>'), Ide.inst.ideConfig.typingDebounceThreshold, (v) -> Ide.inst.ideConfig.typingDebounceThreshold = v);
		search.add("Close search on file opening", new Element('<input type="checkbox"/>'), Ide.inst.ideConfig.closeSearchOnFileOpen, (v) -> Ide.inst.ideConfig.closeSearchOnFileOpen = v);
		categories.push(search);
	}

	override function onDisplay() {
		new Element('
		<div class="settings">
			<div class="settings-header"></div>
			<div class="settings-body">
				<div class="categories"></div>
				<div class="content"><div>
			</div>
		</div>'
		).appendTo(element);

		var categoriesEl = element.find('.categories');
		for (c in categories) {
			var cEl = new Element('<p>${c.name}</p>').appendTo(categoriesEl);
			cEl.on('click', function(e){ selectCategorie(c); });
		}

		// By default open general settings
		selectCategorie(categories[0]);
	}

	override function getTitle() {
		return "Settings";
	}

	function selectCategorie(c : Categorie) {
		var content = element.find('.content');
		content.empty();

		content.append(c.element);
	}

	static var _ = hide.ui.View.register(Settings);
}

class Categorie {
	public var name : String;
	public var element : Element;

	public function new(name: String) {
		this.name = name;
		this.element = new Element('
		<div>
			<h1>${name}</h1>
		</div>');
	}

	public function add(settingsName: String, editElement: Element, value: Dynamic, ?onChange : Dynamic -> Void) {
		var el = new Element('<dl><dt>${settingsName}</dt><dd class="edit"></dd></dl>');
		el.find('.edit').append(editElement);

		if (editElement.is('input[type="checkbox"]'))
			editElement.prop('checked', value);
		else
			editElement.val(value);

		this.element.append(el);

		if (onChange != null)
			editElement.on('change', function(v) {
				var v : Dynamic = null;
				if (editElement.is('input[type="checkbox"]'))
					v = editElement.prop('checked');
				else
					v = Std.parseFloat(editElement.val());

				onChange(v);
				Ide.inst.config.global.save();
			} );
	}
}
