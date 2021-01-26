package hrt.prefab;

class Model extends Object3D {

	var animation : Null<String>;
	var lockAnimation : Bool = false;
	var retargetAnim : Bool = false;
	var retargetIgnore : String = null;

	public function new(?parent) {
		super(parent);
		type = "model";
	}

	override function save() {
		var obj : Dynamic = super.save();
		if( animation != null ) obj.animation = animation;
		if( lockAnimation ) obj.lockAnimation = lockAnimation;
		if( retargetAnim ) obj.retargetAnim = retargetAnim;
		if( retargetIgnore != null && retargetIgnore != "" ) obj.retargetIgnore = retargetIgnore;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		animation = obj.animation;
		lockAnimation = obj.lockAnimation;
		retargetAnim = obj.retargetAnim;
		retargetIgnore = obj.retargetIgnore;
	}

	override function makeInstance(ctx:Context):Context {
		if( source == null)
			return super.makeInstance(ctx);
		ctx = ctx.clone(this);
		#if editor
		try {
		#end
			var obj = ctx.loadModel(source);
			if(obj.defaultTransform != null && children.length > 0) {
				obj.name = "root";
				var root = new h3d.scene.Object();
				root.addChild(obj);
				obj = root;
			}
			#if editor
			for(m in obj.getMeshes())
				m.cullingCollider = new h3d.col.ObjectCollider(m, m.primitive.getBounds().toSphere());
			#end
			if( retargetAnim ) applyRetarget(obj);

			obj.name = name;
			ctx.local3d.addChild(obj);
			ctx.local3d = obj;
			updateInstance(ctx);


			if( animation != null )
				obj.playAnimation(ctx.loadAnimation(animation));

			return ctx;
		#if editor
		} catch( e : Dynamic ) {
			e.message = "Could not load model " + source + ": " + e.message;
			ctx.shared.onError(e);
		}
		#end
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
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
	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Animation">
				<dl>
					<dt>Model</dt><dd><input type="model" field="source"/></dd>
					<dt>Animation</dt><dd><select><option value="">-- Choose --</option></select>
					<dt title="Don\'t save animation changes">Lock</dt><dd><input type="checkbox" field="lockAnimation"></dd>
					<dt>Retarget</dt><dd><input type="checkbox" field="retargetAnim"></dd>
					<dt>Retarget Ignore</dt><dd><input type="text" field="retargetIgnore"></dd>
				</dl>
			</div>
		'),this, function(pname) {
			if( pname == "retargetIgnore" && ctx.properties.isTempChange ) return;
			ctx.onChange(this, pname);
		});

		var select = props.find("select");
		var anims = try ctx.scene.listAnims(source) catch(e: Dynamic) [];
		for( a in anims )
			new hide.Element('<option>').attr("value", ctx.ide.makeRelative(a)).text(ctx.scene.animationName(a)).appendTo(select);
		if( animation != null )
			select.val(animation);
		select.change(function(_) {
			var v = select.val();
			var prev = animation;
			var obj = ctx.getContext(this).local3d;
			ctx.scene.setCurrent();
			if( v == "" ) {
				animation = null;
				obj.stopAnimation();
			} else {
				obj.playAnimation(ctx.rootContext.loadAnimation(v)).loop = true;
				if( lockAnimation ) return;
				animation = v;
			}
			var newValue = animation;
			ctx.properties.undo.change(Custom(function(undo) {
				var obj = ctx.getContext(this).local3d;
				animation = undo ? prev : newValue;
				if( animation == null ) {
					obj.stopAnimation();
					select.val("");
				} else {
					obj.playAnimation(ctx.rootContext.loadAnimation(animation)).loop = true;
					select.val(v);
				}
			}));
		});
	}

	override function getHideProps() : HideProps {
		return {
			icon : "cube", name : "Model", fileSource : ["fbx","hmd"],
			allowChildren : function(t) return Library.isOfType(t,Object3D) || ["material", "shader"].indexOf(t) >= 0,
			onResourceRenamed : function(f) animation = f(animation),
		};
	}
	#end

	static var _ = Library.register("model", Model);

}