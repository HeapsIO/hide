package hrt.ui;

class HuiCategory extends HuiElement {
	public var headerName(get, set) : String;

	inline function set_headerName(s: String) return headerText.text = s;
	inline function get_headerName() return headerText.text;

	static var SRC =
		<hui-category>
			<hui-element id="header"><hui-fmt-text("") id="header-text"/></hui-element>
			<hui-element id="content" __content__ public/>
		</hui-category>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}