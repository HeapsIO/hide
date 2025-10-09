package hidehl.ui;

class Category extends Element {
	public var headerName(get, set) : String;

	inline function set_headerName(s: String) return headerText.text = s;
	inline function get_headerName() return headerText.text;

	static var SRC =
		<category>
			<element id="header"><fmt-text("") id="header-text"/></element>
			<element id="content" __content__ public/>
		</category>

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}
}