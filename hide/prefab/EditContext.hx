package hide.prefab;

#if !macro
import hrt.prefab.Prefab;
#end

class EditContext {
	#if !macro

	#if editor

	public var rootPrefab : hrt.prefab.Prefab;

	var undo : hide.ui.UndoHistory;

	public function new(undo: hide.ui.UndoHistory) {
		this.undo = undo;
	}

	/**
		list of functions to call in the sceneEditor `update()`
	**/
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
		var current = p.save();

		properties.undo.change(Custom(function(b) {
			var old = p.save();
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

		for( o in rootPrefab.shared.root3d)
			getRec([], o);

		return out;
	}
	#end
}

#if domkit

@:access(hide.prefab.EditContext)
class HideJsEditContext2 extends hrt.prefab.EditContext2 {
	var ctx : EditContext;
	var saveKey: String;

	public function new(parent: hrt.prefab.EditContext2, ctx: EditContext) {
		super(parent);
		this.ctx = ctx;
	}

	public function recordUndo(cb: (isUndo:Bool) -> Void) {
		if (parent != null)
			throw "Side effect in a multi edit context";
		ctx.undo.change(Custom(cb));
	}

	public function rebuildInspector() : Void {
		if (parent != null)
			return;
		js.Browser.window.requestAnimationFrame((_) -> ctx.rebuildProperties());
	}

	public function saveSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String, value: Dynamic) : Void {
		if (parent != null)
			return;

		if (value == null) {
			ctx.ide.localStorage.removeItem(getSaveKey(category, key));
			return;
		}
		ctx.ide.localStorage.setItem(getSaveKey(category, key), haxe.Json.stringify(value));
	};

	public function getSetting(category: hrt.prefab.EditContext2.SettingCategory, key: String) : Null<Dynamic> {
		var v = ctx.ide.localStorage.getItem(getSaveKey(category, key));
		if( v == null )
			return null;
		return haxe.Json.parse(v);
	};

	function getSaveKey(category: hrt.prefab.EditContext2.SettingCategory, key: String) {
		var mid = switch(category) {
			case Global:
				"global";
			case SameKind:
				saveKey;
		};

		return 'inspector/$mid/$key';
	}

	public function getScene3d() : h3d.scene.Scene {
		return ctx.scene.s3d;
	}

	public function getScene2d() : h2d.Scene {
		return ctx.scene.s2d;
	}

	public function getCameraController3d():hide.view.CameraController.CameraControllerBase {
		return ctx.scene.editor.cameraController;
	}

	public function getRootObjects3d() : Array<h3d.scene.Object> {
		return @:privateAccess ctx.rootPrefab.shared.root3d.children;
	}

	public function openFile(path:String) : Void {
		if (parent != null)
			return;
		ctx.ide.openFile(path);
	}

	public function rebuildPrefab(prefab:Prefab) {
		ctx.scene.editor.queueRebuild(prefab);
	}

	public function chooseFileSave(path: String, callback:(absPath: String) -> Void, allowNull: Bool = false) : Void {
		hide.Ide.inst.chooseFileSave(path, (relPath) -> {
			callback(hide.Ide.inst.getPath(relPath));
		}, allowNull);
	}

	public function rebuildTree(prefab: Prefab) {
		ctx.scene.editor.sceneTree.refreshItem(prefab);
	}

	public function listMaterialLibraries(path: String) : Array<{path: String, name: String}> {
		return cast ctx.scene.listMatLibraries(path);
	}

	public function openPrefab(path: String, ?afterOpen : (api: hrt.prefab.SceneEditorAPI) -> Void) : Void {
		hide.Ide.inst.openFile(path, null, (view) -> {
			if (afterOpen != null) {
				var prefabView : hide.view.Prefab.Prefab = cast view;
				prefabView.delaySceneEditor(() -> {
					haxe.Timer.delay(() -> afterOpen(new hide.comp.SceneEditor.HideSceneEditorAPI(prefabView.sceneEditor)), 100);
				});
			}
		});
	};

	public function quickError(message: String) {
		Ide.inst.quickError(message);
	}

	public function setTool(tool:hrt.prefab.EditContext2.EditorTool, unique:Bool = true) {

	}
}

#end