package hide.kit;

class Category extends Widget<Null<Bool>> {
	/**
		If this category should be closed by default
	**/
	public var closed = false;

	var name(default, null) : String;
	var openState : Bool;

	var currentSection : js.html.Element;
	var sections: Array<js.html.Element> = [];

	public function new(parent: Element, id: String, name: String) : Void {
		this.name = name;
		super(parent, name);
	}

	#if js
	var jsContent : js.html.Element;
	override function get_nativeContent() return jsContent;
	var headerCheckbox : js.html.InputElement;
	#else
	var hlCategory : hrt.ui.HuiCategory;
	override function get_nativeContent() return hlCategory.content;
	#end

	override function makeSelf(): Void {
		#if js
		native = new hide.Element('
			<kit-category class="open">
				<div class="title"><input type="checkbox" class="header-checkbox"/><kit-label>$name</kit-label></div>
				<div class="collapsable">
					<div class="content">
					</div>
				</div>
			</div>
		')[0];
		var level = 0;
		{
			var parent = parent;
			while(parent != null) {
				if (parent is Category)
					level++;
				parent = parent.parent;
			}
		}
		native.style.setProperty("--level", '$level');
		jsContent = native.querySelector(".content");
		var title = native.querySelector(".title");
		title.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0 || event.target == headerCheckbox)
				return;
			openState = !openState;
			if (closed) {
				saveSetting(SameKind, "openState", openState ? true : null);
			} else {
				saveSetting(SameKind, "openState", openState ? null : false);
			}
			refresh();
		});

		headerCheckbox = cast native.querySelector(".header-checkbox");
		if (value != null) {
			input = headerCheckbox;
			headerCheckbox.addEventListener("input", () -> {
				value = headerCheckbox.checked;
				broadcastValueChange(false);
				toggleOpenState(true);
			});
		} else {
			headerCheckbox.style.display = "none";
		}

		openState = getSetting(SameKind, "openState") ?? !closed;
		refresh();
		addEditMenu(title);

		syncValueUI();

		#else
		native = hlCategory = new hrt.ui.HuiCategory();
		hlCategory.headerName = name;
		#end
	}

	override function getEditMenuContent() : Array<hide.comp.ContextMenu.MenuItem> {
		var content = super.getEditMenuContent();
		content.unshift({isSeparator: true});
		content.unshift({label: "Collapse", click: collapse});
		content.unshift({label: "Collapse All", click: root.collapse.bind()});
		return content;
	}

	override function getChildDisabled():Bool {
		return isDisabled() || value == false;
	}

	override function collapse() {
		toggleOpenState(false);
		super.collapse();
	}

	override function attachChildNative(child: Element) : Void {
		#if js
		// We create "sections" to add non category elements inside,
		// while keeping the categories outside these to help with inner
		// padding of sections
		if (child is Category) {
			currentSection = null;
			jsContent.appendChild(child.native);
		} else {
			if (currentSection == null) {
				currentSection = js.Browser.document.createElement("kit-section");
				jsContent.appendChild(currentSection);
				sections.push(currentSection);
			}
			currentSection.appendChild(child.native);
		}
		#end
	}

	public function toggleOpenState(?force: Bool) {
		openState = force ?? !openState;
		if (closed) {
			saveSetting(SameKind, "openState", openState ? true : null);
		} else {
			saveSetting(SameKind, "openState", openState ? null : false);
		}
		refresh();
	}

	override function syncValueUI() {
		#if js
		if (value != null) {
			refreshDisabled();
			if (headerCheckbox != null && value != null)
				headerCheckbox.checked = value;
		}
		#end
	}

	function makeInput() {
		return null;
	}

	function stringToValue(obj: String) : Null<Bool> {
		if (obj.toLowerCase() == "true")
			return true;
		if (obj.toLowerCase() == "false")
			return false;
		return null;
	}

	function getDefaultFallback() : Null<Bool> {
		return null;
	}

	function refresh() {
		#if js
		native.classList.toggle("open", openState);
		#end
	}
}