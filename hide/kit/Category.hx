package hide.kit;

class Category extends Element {
	var name(default, null) : String;
	var open : Bool;

	public function new(parent: Element, id: String, name: String) : Void {
		this.name = name;
		super(parent, id);
	}

	#if js
	var jsContent : js.html.Element;
	override function get_nativeContent() return jsContent;
	#else
	var hlCategory : hrt.ui.HuiCategory;
	override function get_nativeContent() return hlCategory.content;
	#end

	override function makeSelf(): Void {
		#if js
		native = new hide.Element('
			<kit-category class="open">
				<div class="title">$name</div>
				<div class="collapsable">
					<div class="content">
					</div>
				</div>
			</div>
		')[0];
		jsContent = native.querySelector(".content");
		var title = native.querySelector(".title");
		title.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0)
				return;
			open = !open;
			saveSetting(SameKind, "open", open ? null : false);
			refresh();
		});

		open = getSetting(SameKind, "open") ?? true;
		refresh();
		addEditMenu(title);

		#else
		native = hlCategory = new hrt.ui.HuiCategory();
		hlCategory.headerName = name;
		#end
	}

	function refresh() {
		#if js
		native.classList.toggle("open", open);
		#end
	}
}