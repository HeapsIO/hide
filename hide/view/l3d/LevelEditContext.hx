package hide.view.l3d;
import hide.prefab.Prefab as PrefabElement;
import h3d.scene.Object;

class LevelEditContext extends hide.prefab.EditContext {

	public var elements : Array<PrefabElement>;
	public var rootObjects(default, null): Array<Object>;
	public var rootElements(default, null): Array<PrefabElement>;

	public function new(ctx, elts) {
		super(ctx);
		this.elements = elts;
		rootObjects = [];
		rootElements = [];
		for(elt in elements) {
			if(!Level3D.hasParent(elt, elements)) {
				rootElements.push(elt);
				rootObjects.push(getContext(elt).local3d);
			}
		}
	}

	override function rebuild() {
		properties.clear();
		cleanup();
		if(elements.length > 0) 
			elements[0].edit(this);
	}

	public function cleanup() {
		for( c in cleanups.copy() )
			c();
		cleanups = [];
	}

	override function onChange(p : PrefabElement, pname: String) {
		var level3D : Level3D = cast view;
		level3D.onPrefabChange(p, pname);
	}
}