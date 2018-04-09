package hide.prefab;

class EditContext {

	public var rootContext : Context;

	#if editor
	public var prefabPath : String;
	public var ide(get,never) : hide.Ide;
	public var scene : hide.comp.Scene;
	public var view : hide.view.FileView;
	public var cleanups : Array<Void->Void>;
	public var properties : hide.comp.PropsEditor;
	function get_ide() return hide.Ide.inst;
	public function onChange(p : Prefab, propName : String) { }
	#end

	public function new(ctx) {
		this.rootContext = ctx;
	}

	public function getContext( p : Prefab ) {
		return rootContext.shared.contexts.get(p);
	}

	/**
		Rebuild the edit window
	**/
	public function rebuild() {
	}

	public function getNamedObjects( ?exclude : h3d.scene.Object ) {
		var out = [];

		function getJoint(path:Array<String>,j:h3d.anim.Skin.Joint) {
			path.push(j.name);
			out.push(path.join("."));
			for( j in j.subs )
				getJoint(path, j);
			path.pop();
		}

		function getRec(path:Array<String>, o:h3d.scene.Object) {
			if( o == exclude || o.name == null ) return;
			path.push(o.name);
			out.push(path.join("."));
			for( c in o )
				getRec(path, c);
			var sk = Std.instance(o, h3d.scene.Skin);
			if( sk != null ) {
				var j = sk.getSkinData();
				for( j in j.rootJoints )
					getJoint(path, j);
			}
			path.pop();
		}

		for( o in rootContext.shared.root3d )
			getRec([], o);

		return out;
	}

}
