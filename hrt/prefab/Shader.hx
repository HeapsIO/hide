package hrt.prefab;

class Shader extends Prefab {

	function new(?parent) {
		super(parent);
		props = {};
	}

	public function makeShader( ?ctx : hrt.prefab.Context ) : hxsl.Shader {
		return null;
	}

	public function getShaderDefinition( ctx : hrt.prefab.Context ) : hxsl.SharedShader {
		var s = makeShader(ctx);
		return s == null ? null : @:privateAccess s.shader;
	}

	override function updateInstance(ctx: Context, ?propName) {
		var shaderDef = getShaderDefinition(ctx);
		if( ctx.custom == null || shaderDef == null )
			return;
		syncShaderVars(ctx.custom, shaderDef);
	}

	function syncShaderVars( shader : hxsl.Shader, shaderDef : hxsl.SharedShader ) {
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
			case TVec(_, VFloat):
				if(val != null)
					val = h3d.Vector.fromArray(val);
				else
					val = new h3d.Vector();
			case TSampler2D:
				if( val != null )
					val = hxd.res.Loader.currentInstance.load(val).toTexture();
				else {
					var childNoise = getOpt(hrt.prefab.l2d.NoiseGenerator, v.name);
					if(childNoise != null)
						val = childNoise.toTexture();
				}
			default:
			}
			if(val == null)
				continue;
			setShaderParam(shader,v,val);
		}
	}

	function setShaderParam( shader:hxsl.Shader, v : hxsl.Ast.TVar, value : Dynamic ) {
		Reflect.setProperty(shader, v.name, value);
	}

	function applyShader( obj : h3d.scene.Object, material : h3d.mat.Material, shader : hxsl.Shader ) {
		material.mainPass.addShader(shader);
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var shader = makeShader(ctx);
		if( shader == null )
			return ctx;
		if( ctx.local2d != null ) {
			var drawable = Std.downcast(ctx.local2d, h2d.Drawable);
			if (drawable != null) {
				drawable.addShader(shader);
				ctx.cleanup = function() {
					drawable.removeShader(shader);
				}
			} else {
				var flow = Std.downcast(ctx.local2d, h2d.Flow);
				if (flow != null) {
					@:privateAccess if (flow.background != null) {
						flow.background.addShader(shader);
						ctx.cleanup = function() {
							flow.background.removeShader(shader);
						}
					}
				}
			}
		}
		if( ctx.local3d != null ) {
			var parent = parent;
			var shared = ctx.shared;
			while( parent != null && parent.parent == null && shared.parent != null ) {
				parent = shared.parent.prefab.parent; // reference parent
				shared = shared.parent.shared;
			}
			if( Std.is(parent, Material) ) {
				var material : Material = cast parent;
				for( m in material.getMaterials(ctx) )
					m.mainPass.addShader(shader);
			} else {
				var objs;
				if( parent.type == "object" ) {
					// apply to all immediate children
					objs = [];
					for( c in parent.children )
						for( o in shared.getObjects(c, h3d.scene.Object) )
							objs.push(o);
				} else
					objs = shared.getObjects(parent, h3d.scene.Object);
				for( obj in objs )
					for( m in obj.getMaterials(false) )
						applyShader(obj, m, shader);
			}
		}
		ctx.custom = shader;
		updateInstance(ctx);
		return ctx;
	}

	#if editor

	override function edit( ectx : EditContext ) {
		super.edit(ectx);

		var ctx = ectx.getContext(this);
		var shaderDef = getShaderDefinition(ctx);
		if( shaderDef == null )
			return;

		var group = new hide.Element('<div class="group" name="Shader"></div>');
		var props = [];
		for(v in shaderDef.data.vars) {
			if( v.kind != Param )
				continue;
			var prop = makeShaderParam(v);
			if( prop == null ) continue;
			props.push({name: v.name, t: prop});
		}
		group.append(hide.comp.PropsEditor.makePropsList(props));
		ectx.properties.add(group,this.props, function(pname) {
			ectx.onChange(this, pname);
		});
	}

	function makeShaderParam( v : hxsl.Ast.TVar ) : hrt.prefab.Props.PropType {
		var min : Null<Float> = null, max : Null<Float> = null;
		if( v.qualifiers != null )
			for( q in v.qualifiers )
				switch( q ) {
				case Range(rmin, rmax): min = rmin; max = rmax;
				default:
				}
		return switch( v.type ) {
		case TInt:
			PInt(min == null ? null : Std.int(min), max == null ? null : Std.int(max));
		case TFloat:
			PFloat(min != null ? min : 0.0, max != null ? max : 1.0);
		case TBool:
			PBool;
		case TSampler2D:
			PTexture;
		case TVec(n, VFloat):
			PVec(n);
		default:
			PUnsupported(hxsl.Ast.Tools.toString(v.type));
		}
	}

	override function getHideProps() : HideProps {
		var cl = Type.getClass(this);
		var name = Type.getClassName(cl).split(".").pop();
		return {
			icon : "cog",
			name : name,
			fileSource : cl == hrt.prefab.Shader ? ["hx"] : null,
			allowParent : function(p) return p.to(Object2D) != null || p.to(Object3D) != null || p.to(Material) != null
		};
	}

	#end

}