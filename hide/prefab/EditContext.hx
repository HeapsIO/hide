package hide.prefab;
import hrt.prefab.Prefab;
import hrt.prefab.Context;

class EditContext {

	public var rootContext : Context;

	#if editor

	var updates : Array<Float->Void> = [];

	public var prefabPath : String;
	public var ide(get,never) : hide.Ide;
	public var scene : hide.comp.Scene;
	public var properties : hide.comp.PropsEditor;
	public var cleanups : Array<Void->Void>;
	function get_ide() return hide.Ide.inst;
	public function onChange(p : Prefab, propName : String) {
		var ctx = getContext(p);
		scene.setCurrent();
		if(ctx != null) {
			p.updateInstance(ctx, propName);
			var parent = p.parent;
			while( parent != null ) {
				var pr = parent.getHideProps();
				if( pr.onChildUpdate != null ) pr.onChildUpdate(p);
				parent = parent.parent;
			}
		}

		var refs = rootContext.shared.references.get(p);
		if(refs != null) {
			for(ctx in refs)
				p.updateInstance(ctx, propName);
		}
	}

	public function getCurrentProps( p : Prefab ) : Element {
		throw "Not implemented";
		return null;
	}

	public function addUpdate( f : (dt:Float) -> Void ) {
		updates.push(f);
	}

	public function removeUpdate( f : (dt:Float) -> Void ) {
		for( f2 in updates )
			if( Reflect.compareMethods(f,f2) ) {
				updates.remove(f2);
				break;
			}
	}

	#end

	public function new(ctx) {
		this.rootContext = ctx;
	}

	public function getContext( p : Prefab ) {
		return rootContext.shared.contexts.get(p);
	}

	/**
		Converts screen mouse coordinates into projection into ground.
		If "forPrefab" is used, only this prefab is taken into account for ground consideration (self painting)
	**/
	public function screenToGround( x : Float, y : Float, ?forPrefab : Prefab ) : h3d.col.Point {
		throw "Not implemented";
		return null;
	}

	/**
		Similar to screenToGround but based on 3D coordinates instead of screen ones
	**/
	public function positionToGroundZ( x : Float, y : Float, ?forPrefab : Prefab ) : Float {
		throw "Not implemented";
		return null;
	}

	/**
		Rebuild the edit window
	**/
	public function rebuildProperties() {
	}

	/**
		Force rebuilding makeInstance for the given hierarchy
	**/
	public function rebuildPrefab( p : Prefab ) {
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
			var sk = Std.downcast(o, h3d.scene.Skin);
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
