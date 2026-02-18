package hrt.ui;

#if hui

class HuiCategory extends HuiElement {
	static var SRC =
		<hui-category>
			<hui-element id="header"><hui-icon("dropDown") id="header-icon"/><hui-text("") id="header-text"/></hui-element>
			<hui-element id="content" __content__ public/>
		</hui-category>

	public var headerName(get, set) : String;
	public var isOpen : Bool = true;

	inline function set_headerName(s: String) return headerText.text = s;
	inline function get_headerName() return headerText.text;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		header.onClick = (e) -> {
			isOpen = !isOpen;
			content.visible = isOpen;
			headerIcon.setIcon(isOpen ? "dropDown" : "chevronRight");
		};
	}
}

#end
