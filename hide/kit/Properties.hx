package hide.kit;

class Properties extends Element {
	public var editedPrefabsProperties : Array<Properties> = [];
	var prefab : hrt.prefab.Prefab;
	var registeredElements : Map<String, Element> = [];

	public function new(properties: hide.kit.Properties, parent: Element, id: String, prefab: hrt.prefab.Prefab ) {
		super(properties, parent, id);
		this.prefab = prefab;
	}

	public function register(element: Element) {
		registeredElements.set(element.getIdPath(), element);
	}

	public function broadcastValueChange(input: Input<Dynamic>, isTemporaryEdit: Bool) {
		var idPath = input.getIdPath();

		input.onValueChange(isTemporaryEdit);

		for (childProperties in editedPrefabsProperties) {
			var childElement = childProperties.registeredElements.get(idPath);
			var childInput = Std.downcast(childElement, Type.getClass(input));

			if (childInput != null) {
				childInput.value = input.value;
				childInput.onValueChange(isTemporaryEdit);
			}
		}
	}
}