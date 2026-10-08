package hide.view;
import hrt.ui.*;

class CdbEditor extends HuiView<{}> {
	static var SRC =
		<cdb-editor>
			<hui-tab-container id="tabs" class="bottom-tabs"/>
		</cdb-editor>

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		for (s in hide.Ide.inst.database.sheets) {
			if (s.props.hide)
				continue;
			var tab = new HuiCdbTable(s);
			tab.displayName = s.name;
			tabs.addTab(tab);
		}
	}

	override function getViewName():String {
		return "CDB";
	}

	static var _ = HuiView.register("cdbEditor", CdbEditor);
}
