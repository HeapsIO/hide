package hrt.prefab;

class Model extends Object3D {

	@:s public var animation : Null<String>;
	@:s var lockAnimation : Bool = false;
	@:s var retargetAnim : Bool = false;
	@:s var retargetIgnore : String;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		#if editor
		useAutoCollide = true;
		#end
	}

	override function save() : Dynamic {
		if( retargetIgnore == "" ) retargetIgnore = null;
		return super.save();
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		if( source == null)
			return super.makeObject(parent3d);

		#if editor
		try {
		#end
			var obj = shared.loadModel(source);
			if(obj.defaultTransform != null && children.length > 0) {
				obj.name = "root";
				var root = new h3d.scene.Object();
				root.addChild(obj);
				obj = root;
			}
			#if editor
			for(m in obj.getMeshes())
				if( !Std.isOfType(m,h3d.scene.Skin) )
					m.cullingCollider = new h3d.col.ObjectCollider(m, m.primitive.getBounds().toSphere());
			#end
			if( retargetAnim ) applyRetarget(obj);

			obj.name = name;
			parent3d.addChild(obj);

			if( animation != null )
				obj.playAnimation(shared.loadAnimation(animation));

			return obj;
		#if editor
		} catch( e : Dynamic ) {
			e.message = "Could not load model " + source + ": " + e.message;
			shared.onError(e);
		}
		#end
		return new h3d.scene.Object(parent3d);
	}

	function applyRetarget( obj : h3d.scene.Object ) {
		if( !retargetAnim )
			return;
		var ignorePrefix = [], ignoreNames = new Map();
		if( retargetIgnore != null ) {
			for( i in retargetIgnore.split(",") ) {
				if( i.charCodeAt(i.length-1) == "*".code )
					ignorePrefix.push(i.substr(0,-1));
				else
					ignoreNames.set(i, true);
			}
		}
		for( o in obj.getMeshes() ) {
			var sk = Std.downcast(o, h3d.scene.Skin);
			if( sk == null ) continue;
			for( j in sk.getSkinData().allJoints ) {
				var ignored = ignoreNames.get(j.name);
				if( ignored ) continue;
				for( i in ignorePrefix )
					if( StringTools.startsWith(j.name,i) ) {
						ignored = true;
						break;
					}
				if( !ignored )
					j.retargetAnim = true;
			}
		}
	}

	#if editor

	override function onEditorTreeChanged(child:Prefab):hrt.prefab.Prefab.TreeChangedResult {

		// Correctly handle changes in hierachy in case the model has a default transform
		if (Std.downcast(child, Object3D) != null) {
			return Rebuild;
		}
		return super.onEditorTreeChanged(child);
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Animation">
				<dl>
					<dt>Model</dt><dd><input type="model" field="source"/></dd>
					<dt/><dd><input type="button" value="Change All" id="changeAll"/></dd>
					<dt>Animation</dt><dd><input id="anim" value="--- Choose ---"></dd>
					<dt title="Don\'t save animation changes">Lock</dt><dd><input type="checkbox" field="lockAnimation"></dd>
					<dt>Retarget</dt><dd><input type="checkbox" field="retargetAnim"></dd>
					<dt>Retarget Ignore</dt><dd><input type="text" field="retargetIgnore"></dd>
				</dl>
			</div>
		'),this, function(pname) {
			if( pname == "retargetIgnore" && ctx.properties.isTempChange ) return;

			if (pname == "source")
				ctx.scene.editor.queueRebuild(this);

			ctx.onChange(this, pname);
		});

		var changeAllbtn = props.find("#changeAll");
		changeAllbtn.on("click",function() hide.Ide.inst.chooseFile(["fbx", "l3d"] , function (path) {
			ctx.scene.editor.changeAllModels(this, path);
		}));


		var anims = try ctx.scene.listAnims(source) catch(e: Dynamic) [];
		var elts: Array<hide.comp.Dropdown.Choice> = [];
		for( a in anims )
			elts.push({id : ctx.ide.makeRelative(a), ico : null, text : ctx.scene.animationName(a), classes : ["compact"]});


		var select = new hide.comp.Select(null, props.find("#anim"), elts);
		select.value = animation;
		select.onChange = function(newAnim : String) {
			var v = newAnim;
			var prev = animation;
			var obj = local3d;
			ctx.scene.setCurrent();
			if( v == "" ) {
				animation = null;
				obj.stopAnimation();
			} else {
				obj.playAnimation(shared.loadAnimation(v)).loop = true;
				if( lockAnimation ) return;
				animation = v;
			}
			var newValue = animation;
			ctx.properties.undo.change(Custom(function(undo) {
				var obj = local3d;
				animation = undo ? prev : newValue;
				if( animation == null ) {
					obj.stopAnimation();
				} else {
					obj.playAnimation(shared.loadAnimation(animation)).loop = true;
				}
				select.value = animation;
			}));
		};
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "cube", name : "Model", fileSource : ["fbx","hmd"],
			allowChildren : function(t) return Prefab.isOfType(t,Object3D) || Prefab.isOfType(t,Material) || Prefab.isOfType(t,Shader) || Prefab.isOfType(t, hrt.prefab.fx.AnimEvent),
			onResourceRenamed : function(f) animation = f(animation),
		};
	}
	#end

	static var _ = Prefab.register("model", Model);

}