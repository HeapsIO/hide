package hide.prefab.propsEditor;

class AnyPropsEditor<T:hxd.impl.AnyProps> {
	public var props : T;

	public static function makeEditor(props: hxd.impl.AnyProps) {
		var propsClass = Type.getClass(props);
		var editorClass = null;
		while (propsClass != null) {
			editorClass = editors.get(Type.getClassName(propsClass));
			if (editorClass != null)
				break;
			propsClass = cast Type.getSuperClass(propsClass);
		}

		if (editorClass == null)
			throw "No registered editor for material of class";

		var editor : AnyPropsEditor<Dynamic> = Type.createEmptyInstance(editorClass);
		editor.props = props;
		return editor;
	}

	static function registerEditor(propsClass: Class<hxd.impl.AnyProps>, editorClass: Class<AnyPropsEditor<Dynamic>>) : Bool {
		editors.set(Type.getClassName(propsClass), editorClass);
		return true;
	}

	/** add element to root**/
	public function edit2(ctx: hrt.prefab.EditContext2, root: hide.kit.Element, ?customProps: Dynamic, onChange: (tmp: Bool) -> Void = null) : Void {
	}

	static var editors : Map<String, Class<AnyPropsEditor<Dynamic>>> = [];
}