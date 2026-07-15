package hrt.ui;

#if hui

class HuiCategory extends HuiElement {
	static var SRC =
		<hui-category>
			<hui-element id="header"><hui-element id="header-icon"/><hui-text("") id="header-text"/></hui-element>
			<hui-element id="content" __content__ public/>
		</hui-category>

	public var headerName(get, set) : String;
	public var isOpen(default, set) : Bool = true;

	inline function set_headerName(s: String) return headerText.text = s;
	inline function get_headerName() return headerText.text;

	function set_isOpen(v) {isOpen = v; refreshStyle(); return isOpen;}

	public function new(?headerName : String, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.headerName = headerName;

		header.onClick = (e) -> {
			isOpen = !isOpen;
		};

		isOpen = isOpen;
	}

	function refreshStyle() {
		dom.toggleClass("open", isOpen);
		content.visible = isOpen;
	}
}

#end
