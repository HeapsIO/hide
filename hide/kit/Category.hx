package hide.kit;

class Category extends Element {
	var name(default, null) : String;

	public function new(parent: Element, id: String, name: String) : Void {
		this.name = name;
		super(parent, id);
	}

	#if js
	var jsContent : js.html.Element;
	override function get_nativeContent() return jsContent;
	#end

	override function makeSelf(): Void {
		#if js
		native = new hide.Element('
			<div class="group2 open" name="$name" style="--level: 0">
				<div class="title">$name</div>
				<div class="content"></div>
			</div>
		')[0];
		jsContent = native.querySelector(".content");
		var title = native.querySelector(".title");
		title.addEventListener("mousedown", (event: js.html.MouseEvent) -> {
			if (event.button != 0)
				return;

			native.classList.toggle("open");
		});
		#else
		throw "HideKitHL Implement";
		#end
	}
}