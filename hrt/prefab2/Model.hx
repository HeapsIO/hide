package hrt.prefab2;

class Model extends Object3D {

	@:s public var animation : Null<String>;
	@:s var lockAnimation : Bool = false;
	@:s var retargetAnim : Bool = false;
	@:s var retargetIgnore : String;

	public function new(?parent, shared: ContextShared) {
		super(parent, shared);
	}

	override function save(to: Dynamic) : Dynamic {
		if( retargetIgnore == "" ) retargetIgnore = null;
		return super.save(to);
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
			for(m in obj.getMeshes())
				if( !Std.isOfType(m,h3d.scene.Skin) )
					m.cullingCollider = new h3d.col.ObjectCollider(m, m.primitive.getBounds().toSphere());
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

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		polys3D = null;
		boundingSphere = null;
	}

    var polys3D = null;
    var boundingSphere = null;
    override function localRayIntersection(ray : h3d.col.Ray ) : Float {
        if( polys3D == null ) {
            polys3D = [];
            var bounds = local3d.getBounds();
			bounds.transform(local3d.getAbsPos().getInverse());
            boundingSphere = bounds.toSphere();
            for( m in getObjects(h3d.scene.Mesh) ) {
                var p = cast(m.primitive, h3d.prim.HMDModel);
               	var col = cast(cast(p.getCollider(), h3d.col.Collider.OptimizedCollider).b, h3d.col.PolygonBuffer);
                polys3D.push({ col : col, mat : m.getRelPos(local3d).getInverse() });
            }
        }

        if( boundingSphere.rayIntersection(ray,false) < 0 )
            return -1.;

        var minD = -1.;
        for( p in polys3D ) {
            var ray2 = ray.clone();
            ray2.transform(p.mat);
            var d = p.col.rayIntersection(ray2, true);
            if( d > 0 && (d < minD || minD == -1)  )
                minD = d;
        }

        return minD;
    }

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Animation">
				<dl>
					<dt>Model</dt><dd><input type="model" field="source"/></dd>
					<dt/><dd><input type="button" value="Change All" id="changeAll"/></dd>
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

		var changeAllbtn = props.find("#changeAll");
		changeAllbtn.on("click",function() hide.Ide.inst.chooseFile(["fbx", "l3d"] , function (path) {
			ctx.scene.editor.changeAllModels(this, path);
		}));

		var select = props.find("select");
		var anims = try ctx.scene.listAnims(source) catch(e: Dynamic) [];
		for( a in anims )
			new hide.Element('<option>').attr("value", ctx.ide.makeRelative(a)).text(ctx.scene.animationName(a)).appendTo(select);
		if( animation != null )
			select.val(animation);
		select.change(function(_) {
			var v = select.val();
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
					select.val("");
				} else {
					obj.playAnimation(shared.loadAnimation(animation)).loop = true;
					select.val(v);
				}
			}));
		});
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return {
			icon : "cube", name : "Model", fileSource : ["fbx","hmd"],
			allowChildren : function(t) return Prefab.isOfType(t,Object3D) || Prefab.isOfType(t,Material) || Prefab.isOfType(t,Shader) || Prefab.isOfType(t, hrt.prefab2.fx.AnimEvent),
			onResourceRenamed : function(f) animation = f(animation),
		};
	}
	#end

	static var _ = Prefab.register("model", Model);

}