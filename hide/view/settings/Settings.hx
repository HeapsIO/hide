package hide.view.settings;

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

class Settings extends hide.ui.View<{}> {
	public var categories : Array<Categorie>;

	public function new( ?state ) {
		super(state);

		categories = [];
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

		// By default open first categorie
        if (categories.length > 0)
		    selectCategorie(categories[0]);
	}

	function selectCategorie(c : Categorie) {
		var content = element.find('.content');
		content.empty();

		content.append(c.element);
	}


	settings.register("oeoeoe", [Array<zae])
	function getCategorie(name : String) {
		var res = null;
		for (c in categories) {
			if (c.name == name)
				return c;
		}
		return res;
	}
}