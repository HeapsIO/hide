package hrt.ui;

#if hui
class HuiPrefabInspectorHeader extends HuiElement {
	static var SRC = <hui-prefab-inspector-header>
		<hui-element class="horizontal">
			<hui-checkbox id="enable-el"/>
			<hui-input-box id="name-el"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Type :")/>
			<hui-text id="type-el" class="italic"/>
		</hui-element>
	</hui-prefab-inspector-header>

	var prefabs : Array<hrt.prefab.Prefab>;

	public function new(view : hide.view.Prefab, prefabs: Array<hrt.prefab.Prefab>, ?parent: h2d.Object) {
		super(parent);
		this.prefabs = prefabs;
		initComponent();
		refresh();

		enableEl.onValueChanged = () -> {
			view.setEnable(prefabs, enableEl.value);
		}

		nameEl.onChange = (isTemp) -> {
			if (isTemp)
				return;

			var oldName = prefabs[0].name;
			var newName = nameEl.text;
			function apply(isUndo) {
				for (i in 0...prefabs.length) {
					prefabs[i].name = isUndo ? oldName : newName;
					view.tryMake(prefabs[i]);
				}
				nameEl.text = isUndo ? oldName : newName;
			}
			apply(false);
			view.undo.record(apply, true);
		}
	}

	public function refresh() {
		enableEl.value = getCommonProperty(prefabs, "enabled") ?? false;
		var commonName = getCommonProperty(prefabs, "name");
		nameEl.text = commonName ?? "-";
		nameEl.disabled = commonName == null;
		var commonClass = hrt.tools.ClassUtils.getCommonClassInstance(prefabs, hrt.prefab.Prefab);
		typeEl.text = Type.getClassName(commonClass).split(".").pop();
	}

	function getCommonProperty(prefabs : Array<hrt.prefab.Prefab>, prop : String) {
		if (prefabs == null || prefabs.length == 0)
			return null;
		var p = Reflect.field(prefabs[0], prop);
		for (prefab in prefabs) {
			var p2 = Reflect.field(prefab, prop);
			if (p2 != p)
				return null;
		}

		return p;
	}
}
#end