package hrt.ui;

#if hui
class HuiCdbInspector extends HuiElement {
	static var SRC = <hui-cdb-inspector>
	</hui-cdb-inspector>

	public function new(type : cdb.Sheet, props: Dynamic, ?prefab: hrt.prefab.Prefab, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();

		new HuiPropsInspector(@:privateAccess type.sheet, props, false, prefab, this);
	}
}

class HuiPropsInspector extends HuiElement {
	static var SRC = <hui-props-inspector>
	</hui-props-inspector>

	var sheet : cdb.Data.SheetData;
	var props : Dynamic;
	var sub: Bool;

	/** Prefab owning the edited props, reported to the editor undo **/
	var prefab : hrt.prefab.Prefab;

	public function new(sheet: cdb.Data.SheetData, props: Dynamic, sub: Bool = false, ?prefab: hrt.prefab.Prefab, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.makeInteractive();

		this.sheet = sheet;
		this.props  = props;
		this.sub = sub;
		this.prefab = prefab;

		build();
	}

	function build() {
		this.removeChildren();

		var addableProp = [];
		var removableProp = [];
		for (c in sheet.columns) {
			var isRemovable = sub && c.opt;

			if (sub && !Reflect.hasField(props, c.name)) {
				if (isRemovable)
					addableProp.push(c );
				continue;
			}

			removableProp.push(c);

			var field = new HuiElement(this);
			field.dom.addClass("horizontal");

			var label = new HuiText(c.name, field);
			label.dom.addClass("label");

			var insp : HuiElement = null;
			var fieldName = c.name;
			switch (c.type) {
				case TId, TString, TDynamic, TFile:
					if (c.kind == Script) {
						var el = new HuiCodeEditor(field);
						el.value = Reflect.field(props, fieldName);
						@:privateAccess el.editor.onFocusLost = (e) -> {
							onValueChanged(props, fieldName, el.value);
						}
						insp = el;
					} else {
						var el = new HuiInputBox(field);
						el.text = Reflect.field(props, fieldName);
						el.onChange = (isTempValue) -> { if (isTempValue) return; onValueChanged(props, fieldName, el.text); };
						insp = el;
					}
				case TBool:
					var el = new HuiCheckbox(field);
					el.value = Reflect.field(props, fieldName);
					el.onValueChanged = () -> { onValueChanged(props, fieldName, el.value); };
					insp = el;
				case TInt, TFloat:
					var el = new HuiSlider(field);
					el.value = Reflect.field(props, fieldName);
					el.onValueChanged = (isTempValue) -> { if (isTempValue) return; onValueChanged(props, fieldName, el.value); };
					insp = el;
				case TEnum(values):
					var el = new HuiSelect(field);
					var isStr = c.enumStr == true;
					el.items = [for (oIdx => o in values) { label: o, value: isStr ? (o : Dynamic) : oIdx }];
					if (c.opt)
						el.items.insert(0, { label: "None", value: isStr ? null : -1 });
					el.value = Reflect.field(props, fieldName);
					el.onValueChanged = () -> { onValueChanged(props, fieldName, el.value); };
					insp = el;
				case TProperties:
					var s = @:privateAccess hide.Ide.inst.database.getSheet('${sheet.name}@${fieldName}').sheet;
					var el = new HuiPropsInspector(s, Reflect.field(props, fieldName), true, prefab, field);
					insp = el;
				default:
					var el = new HuiText("inspector isn't supported for this value", field);
					insp = el;
			}

			insp.dom.addClass("value");
			if (sub) {
				label.onClick = (e : hxd.Event) -> {
					if (e.button != 1)
						return;
					uiBase.contextMenu([{ label: "Delete", click: () -> {
						onValueChanged(props, fieldName, null);
					} }]);
				}
			}
		}

		var sel = new HuiSelect(this);
		sel.items = [ for (c in addableProp) { label: c.name, value: c }];
		sel.items.sort((a, b) -> Reflect.compare(a.value.name, b.value.name));
		sel.items.insert(0, { label: "- Choose -", value: null });
		sel.value = null;

		sel.onValueChanged = () -> {
			if (sel.value == null)
				return;

			var defaultValue : Dynamic = null;
			var valueType : cdb.Data.ColumnType = sel.value.type;
			switch (valueType) {
				case TEnum(values) if (sel.value.enumStr == true):
						defaultValue = values[0];
				case TFloat, TInt, TEnum(_):
						defaultValue = 0;
				case TBool:
						defaultValue = true;
				default:
			}

			onValueChanged(props, sel.value.name, defaultValue);
			build();
		}
	}

	function onValueChanged(object: Dynamic, field: String, value : Dynamic) {
		var oldValue = Reflect.field(object, field);
		var newValue = value;

		function exec(isUndo : Bool) {
			if (Reflect.hasField(props, field) && (oldValue == null && isUndo || newValue == null && !isUndo))
				Reflect.deleteField(object, field);
			else
				Reflect.setField(object, field, isUndo ? oldValue : newValue);
			build();
		}

		exec(false);
		var prefabUndo = Std.downcast(getView().undo, hide.view.PrefabUndo);
		if (prefabUndo != null && prefab != null)
			prefabUndo.recordPrefabs(exec, true, [prefab]);
		else
			getView().undo.record(exec, true);
	}
}

#end