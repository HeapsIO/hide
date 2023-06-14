package hide.prefab;

import hrt.prefab.Prefab;

class EditContext {

	#if editor

	var updates : Array<Float->Void> = [];

	public var ide(get,never) : hide.Ide;
	public var scene : hide.comp.Scene;
	public var properties : hide.comp.PropsEditor;
	public var cleanups : Array<Void->Void>;
	function get_ide() return hide.Ide.inst;

	public function onChange(p : Prefab, propName : String) {

		p.updateInstance(propName);

		var parent = p.parent;
		while( parent != null ) {
			var pr = parent.getHideProps();
			if( pr.onChildUpdate != null ) pr.onChildUpdate(p);
				parent = parent.parent;
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

	public function makeChanges( p : Prefab, f : Void -> Void ) @:privateAccess {
		var current = {};
		p.save(current);
		properties.undo.change(Custom(function(b) {
			var old = {}
			p.save(old);
			p.load(current);
			current = old;
			rebuildProperties();
			onChange(p, null);
		}));
		f();
		rebuildProperties();
		onChange(p, null);
	}

	#end

	public function new() {
	}

	/*public function getContext( p : Prefab ) {
		return rootContext.shared.contexts.get(p);
	}*/

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
	public function rebuildPrefab( p : Prefab, ?sceneOnly=false) {
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

		for( o in scene.s3d)
			getRec([], o);

		return out;
	}

}
