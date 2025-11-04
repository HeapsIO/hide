package hide.prefab.materialEditor;

class MaterialEditor<T:h3d.mat.Material> extends hrt.prefab.Prefab {
	public var material : T;

	public static function makeEditor(material: h3d.mat.Material) {
		var materialClass = Type.getClass(material);
		var editorClass = null;
		while (materialClass != null) {
			editorClass = editors.get(Type.getClassName(materialClass));
			if (editorClass != null)
				break;
			materialClass = cast Type.getSuperClass(materialClass);
		}

		if (editorClass == null)
			throw "No registered editor for material of class";

		var editor : MaterialEditor<Dynamic> = Type.createEmptyInstance(editorClass);
		editor.material = material;
		return editor;
	}

	static function registerEditor(materialClass: Class<h3d.mat.Material>, editorClass: Class<MaterialEditor<Dynamic>>) : Bool {
		editors.set(Type.getClassName(materialClass), editorClass);
		return true;
	}

	static var editors : Map<String, Class<MaterialEditor<Dynamic>>> = [];
}