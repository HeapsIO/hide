package hide.view;

class Gym extends hide.ui.View<{}> {
	override function onDisplay() {
		element.empty();
		element.addClass("hide-gym");

		{
			var toolbar = section(element, "Buttons");
			toolbar.append(new Element("<h1>Button</h1>"));
			toolbar.append(new Element('<fancy-button><span class="ico ico-gear"></span></fancy-button>'));

			toolbar.append(new Element("<h1>Selected</h1>"));
			toolbar.append(new Element('<fancy-button class="selected"><span class="ico ico-gear"></span></fancy-button>'));

			toolbar.append(new Element("<h1>Text button</h1>"));

			toolbar.append(new Element('<fancy-button><span class="label">Options</span></fancy-button>'));
			toolbar.append(new Element('<fancy-separator></fancy-separator>'));
			toolbar.append(new Element('<fancy-button class="selected"><span class="label">Options</span></fancy-button>'));

			toolbar.append(new Element("<h1>Icon and text button</h1>"));
			toolbar.append(new Element('<fancy-button><span class="ico ico-gear"></span><span class="label">Options</span></fancy-button>'));
			toolbar.append(new Element('<fancy-separator></fancy-separator>'));
			toolbar.append(new Element('<fancy-button class="selected"><span class="ico ico-gear"></span><span class="label">Options</span></fancy-button>'));


			toolbar.append(new Element("<h1>Icon and really long text button</h1>"));
			toolbar.append(new Element('<fancy-button><span class="ico ico-gear"></span><span class="label">Lorem ispum sit dolor amet</span></fancy-button>'));

			toolbar.append(new Element("<h1>Icon and dropdown aside </h1>"));
			toolbar.append(new Element('
				<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-eye"></span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>

					<fancy-separator></fancy-separator>

					<fancy-button class="selected">
						<span class="ico ico-eye"></span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>
				</fancy-toolbar>
				'));

			toolbar.append(new Element("<h1>With dropdown</h1>"));
			toolbar.append(new Element('
				<fancy-toolbar>
					<fancy-button class="dropdown">
						<span class="label">Options</span>
					</fancy-button>
					<fancy-separator></fancy-separator>
					<fancy-button class="dropdown">
						<span class="ico ico-filter"></span>
					</fancy-button>
				</fancy-toolbar>
			'
			)
			);

			toolbar.append(new Element("<h1>Icon text and dropdown aside </h1>"));
			toolbar.append(new Element('
				<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-gear"></span>
						<span class="label">Options</span>
					</fancy-button>
					<fancy-button class="compact">
						<span class="ico ico-chevron-down"></span>
					</fancy-button>
			'));


			toolbar.find(".compact, .dropdown").click((e:js.jquery.Event) -> {
				hide.comp.ContextMenu.createDropdown(cast e.currentTarget, getContextMenuContent(), {});
			});

			toolbar.append(new Element("<h1>Toolbar</h1>"));
			toolbar.append(new Element(
				'<fancy-toolbar>
					<fancy-button>
						<span class="ico ico-home"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-clipboard"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-gear"></span>
					</fancy-button>
					<fancy-separator></fancy-separator>
					<fancy-button class="selected">
						<span class="ico ico-pencil"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-eraser"></span>
					</fancy-button>
					<fancy-button>
						<span class="ico ico-paint-brush"></span>
					</fancy-button>
				</fancy-toolbar>'));
		}
	}

	static function section(parent: Element, name: String) : Element {
		return new Element('<details><summary>$name</summary></details>').appendTo(parent);
	}

	static function getContextMenuContent() : Array<hide.comp.ContextMenu.MenuItem> {

		var radioState = 0;
		return [
			{label: "Label"},

			{isSeparator: true},
			{label: "Basic"},
			{label: "Disabled", enabled: false},
			{label: "Icon", icon: "pencil"},
			{label: "Checked", checked: true},
			{label: "Unchecked", checked: false},
			{label: "Keys", keys: "Ctrl+Z"},
			{label: "Long Keys", keys: "Ctrl+Shift+Alt+Z"},
			{label: "Keys Disabled", keys: "Ctrl+D", enabled: false},

			{label: "Radio", isSeparator: true},
			{label: "Green", radio: () -> radioState == 0, click: () -> radioState = 0, stayOpen: true },
			{label: "Blue", radio: () -> radioState == 1, click: () -> radioState = 1, stayOpen: true },
			{label: "Red", radio: () -> radioState == 2, click: () -> radioState = 2, stayOpen: true },

			{label: "Edit", isSeparator: true},
			{label: "Copy", keys: "Ctrl+C"},
			{label: "Paste", keys: "Ctrl+V"},
			{label: "Cut", keys: "Ctrl+X"},

			{label: "Menus", isSeparator: true},
			{label: "Submenu", menu: [
				{label: "Submenu item 1"},
				{label: "Submenu item 2"},
				{label: "Submenu item 3"},
			]},
			{label: "Very long", menu: [
				for (i in 0...200) {label: 'Item $i'}
			]}
		];
	}

	static var _ = hide.ui.View.register(Gym);
}