package hrt.ui;

#if hui
class HuiFilePicker extends HuiElement {
	static var SRC = <hui-file-picker>
		<hui-text id="path"/>
	</hui-file-picker>

	public var value(default, set) : String;

	public function new(?parent) {
		super(parent);
		initComponent();

		this.onClick = (e: hxd.Event) -> {
			hxd.File.browse((select) -> {
				value = select.fileName;
				onValueChanged();
			}, {fileTypes: [{name: "prefab, l3d, fx", extensions: ["prefab", "l3d", "fx"]}]});
		}
	}

	public function set_value(v: String) {
		path.text = v;
		return value = v;
	}

	public dynamic function onValueChanged() {}
}

#end