package hide.kit;

class Category extends Element {
	var name(default, null) : String;

	public function new(ctx: hide.prefab.EditContext, parent: Element, id: String, name: String) : Void {
		this.name = name;
		super(ctx, parent, id);
	}

	#if js
	var jsContent : js.html.Element;
	override function get_wrapContent() return jsContent;
	#end

	override function makeWrap(): WrappedElement {
		#if js
		var e = new hide.Element('
			<div class="group2 open" name="$name" style="--level: 0">
				<div class="title">$name</div>
				<div class="content"></div>
			</div>
		')[0];
		jsContent = e.querySelector(".content");
		var title = e.querySelector(".title");
		title.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0)
				return;

			e.classList.toggle("open");
		});

		return e;
		#else
		throw "HideKitHL Implement";
		#end
	}
}