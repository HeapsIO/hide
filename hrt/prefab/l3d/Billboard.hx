package hrt.prefab.l3d;

class BillboardShader extends hxsl.Shader {
	static var SRC = {
		@param var scale:Float;
		@:import h3d.shader.BaseMesh;
		function vertex() {
			var newModelView = mat4(
				vec4(camera.view[0].x, camera.view[1].x, camera.view[2].x, global.modelView[0].w),
				vec4(camera.view[0].y, camera.view[1].y, camera.view[2].y, global.modelView[1].w),
				vec4(camera.view[0].z, camera.view[1].z, camera.view[2].z, global.modelView[2].w),
				vec4(0, 0, 0, 1));

			// scale
			newModelView = mat4(
				vec4(scale /*length(global.modelView[0].xyz)*/, 0.0, 0.0, 0.0),
				vec4(0.0, scale /*length(global.modelView[1].xyz)*/, 0.0, 0.0),
				vec4(0.0, 0.0, scale /*length(global.modelView[2].xyz)*/, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)) * newModelView;

			// Fix rotation
			newModelView = mat4(vec4(1, 0, 0, 0), vec4(0, -1, 0, 0), vec4(0, 0, -1, 0), vec4(0, 0, 0, 1)) * newModelView;

			transformedPosition = relativePosition * newModelView.mat3x4();
			transformedNormal = (input.normal * newModelView.mat3()).normalize();
		}
	};
}

class BillboardObj extends h3d.scene.Mesh {
	var prim:h3d.prim.Polygon;
	var shader:BillboardShader;

	public var billboardScale:Float = 1.0;

	public var texture(get, set):h3d.mat.Texture;

	function set_texture(tex:h3d.mat.Texture):h3d.mat.Texture {
		return material.texture = tex;
	}

	function get_texture():h3d.mat.Texture {
		return material.texture;
	}

	public var color(get, set):h3d.Vector4;

	function set_color(col:h3d.Vector4):h3d.Vector4 {
		return material.color = col;
	}

	function get_color():h3d.Vector4 {
		return material.color;
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		shader.scale = billboardScale;
		super.sync(ctx);
	}

	public function new(?tile:h3d.mat.Texture, ?parent:h3d.scene.Object) {
		var shape:hrt.prefab.l3d.Polygon.Shape = Quad(0);
		var cache = hrt.prefab.l3d.Polygon.getPrimCache();
		prim = cache.get(shape);
		if (prim == null)
			prim = Polygon.createPrimitive(shape);
		super(prim, null, parent);

		shader = new BillboardShader();
		material.mainPass.addShader(shader);
		material.mainPass.setBlendMode(Alpha);
		material.mainPass.setPassName("afterTonemapping");
		texture = tile;
	}

	/* ignore parent shaders hack*/
	override public function getMaterials(?a:Array<h3d.mat.Material>, recursive = true) {
		return [];
	}
}
