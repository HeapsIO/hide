package hrt.prefab2.l3d;

class ModelLibraryOptimizer extends Object3D {

	#if !editor

	public var modelLibrary : ModelLibrary;
	public var clear = false;

	public function postChildrenMakeInstance( ctx: InstanciateContext ) : Void {
		modelLibrary = getOpt(ModelLibrary, null, true);
		if ( modelLibrary == null )
			throw "Missing modelLibrary as children";
		modelLibrary.clear = clear;
		for ( c in @:privateAccess ctx.local3d.children.copy() ) {
			if ( c != null )
				modelLibrary.optimize(c);
		}
	}

	#else

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "square", name : "Model Library Optimizer" };
	}

	#end

	static var _ = Prefab.register("modelLibOptimizer", ModelLibraryOptimizer);

}