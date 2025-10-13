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
	#else
	var hlCategory : hidehl.ui.HuiCategory;
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

			native.classList.toggle("open");
		});
		#else
		native = hlCategory = new hidehl.ui.HuiCategory();
		hlCategory.headerName = name;
		#end
	}
}