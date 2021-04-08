package hrt.prefab;

class Shader extends Prefab {

	public function makeShader( ?ctx : hrt.prefab.Context ) : hxsl.Shader {
		return null;
	}

	public function getShaderDefinition( ?ctx : hrt.prefab.Context ) : hxsl.SharedShader {
		var s = makeShader(ctx);
		return s == null ? null : @:privateAccess s.shader;
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
				for( obj in shared.getObjects(parent, h3d.scene.Object) )
					for( m in obj.getMaterials(false) )
						m.mainPass.addShader(shader);
			}
		}
		ctx.custom = shader;
		updateInstance(ctx);
		return ctx;
	}

}