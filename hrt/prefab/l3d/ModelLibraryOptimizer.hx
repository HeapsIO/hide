package hrt.prefab.l3d;

class ModelLibraryOptimizer extends Object3D {

	#if !editor

	public var modelLibrary : ModelLibrary;
	public var clear = false;

	public function postMake( ctx : Context ) {
		modelLibrary = getOpt(ModelLibrary, null, true);
		if ( modelLibrary == null )
			throw "Missing modelLibrary as children";
		modelLibrary.clear = clear;
		for ( c in @:privateAccess ctx.local3d.children.copy() ) {
			if ( c != null )
				modelLibrary.optimize(c);
		}
	}
	override function make( ctx : Context ) : Context {
		if( !enabled )
			return ctx;
		ctx = super.make(ctx);
		postMake(ctx);
		return ctx;
	}

	#else

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Model Library Optimizer" };
	}

	#end

	static var _ = Library.register("modelLibOptimizer", ModelLibraryOptimizer);

}