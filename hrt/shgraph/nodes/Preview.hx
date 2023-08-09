package hrt.shgraph.nodes;

import h3d.scene.Mesh;

using hxsl.Ast;

@name("Preview")
@description("Preview node, just to debug :)")
@group("Output")
@width(100)
@noheader()
class Preview extends ShaderNode {

	@input("Input") var input = SType.Vec4;

	public var variable : TVar;

	override public function build(key : String) : TExpr {

		return {
				p : null,
				t : TVoid,
				e : TBinop(OpAssign, {
					e: TVar(variable),
					p: null,
					t: variable.type
				}, input.getVar(variable.type))
			};

	}

	#if editor
	public var shaderGraph : ShaderGraph;
	var nodePreview : js.jquery.JQuery;
	var cube : Mesh;
	var scene : hide.comp.Scene;
	var currentShaderPreview : hxsl.DynamicShader;
	var currentShaderDef : hrt.prefab.ContextShared.ShaderDef;
	public var config : hide.Config;

	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		for (c in ShaderNode.availableVariables) {
			if (c.name == "pixelColor") {
				this.variable = c;
			}
		}

		if (this.variable == null) {
			throw ShaderException.t("The preview is not available", this.id);
		}
		var element = new hide.Element('<div style="width: 100px; height: 100px"><div class="preview-parent" top="-10px" ><div class="node-preview" style="height: 100px" ></div></div></div>');
		nodePreview = element.find(".node-preview");
		scene = new hide.comp.Scene(config, null, nodePreview);

		scene.onReady = function() {
			var prim = new h3d.prim.Cube();
			prim.addUVs();
			prim.addNormals();
			cube = new Mesh(prim, scene.s3d);
			scene.s3d.camera.pos = new h3d.Vector(0.5, 3.4, 0.5);
			scene.s3d.camera.target = new h3d.Vector(0.5, 0.5, 0.5);
			var light = new h3d.scene.pbr.DirLight(scene.s3d.camera.target.sub(scene.s3d.camera.pos), scene.s3d);
			light.setPosition(scene.s3d.camera.pos.x, scene.s3d.camera.pos.y, scene.s3d.camera.pos.z);
			scene.s3d.camera.zoom = 1;
			scene.init();
			onMove();
			computeOutputs();
		};

		elements.push(element);
		return elements;
	}

	public function onMove(?x : Float, ?y : Float, zoom : Float = 1.) {
		// var top : Float;
		// var left : Float;
		// var parent = nodePreview.parent();
		// if (x != null && y != null) {
		// 	left = x;
		// 	top = y;
		// } else {
		// 	var offsetWindow = nodePreview.closest(".heaps-scene").offset();
		// 	var offset = nodePreview.closest("foreignObject").offset();
		// 	if (offsetWindow == null || offset == null) return;
		// 	top = offset.top - offsetWindow.top - 32;
		// 	left = offset.left - offsetWindow.left;
		// }
		// nodePreview.closest(".prop-group").attr("transform", 'translate(0, -5)');
		nodePreview.closest(".properties-group").children().first().css("fill", "#000");
		// parent.css("top", top/zoom + 17);
		// parent.css("left", left/zoom);
		// parent.css("zoom", zoom);
	}

	function onResize() {
		if( cube == null ) return;

	}

	override public function computeOutputs() {
		if (currentShaderPreview != null) {
			for (m in cube.getMaterials()) {
				m.mainPass.removeShader(currentShaderPreview);
			}
			currentShaderPreview = null;
		}

		if (scene == null || input == null || input.isEmpty()) return;

		if (@:privateAccess scene.window == null)
			return;
		scene.setCurrent();

		var shader : hxsl.DynamicShader = null;
		try {
			var shaderGraphDef = shaderGraph.compile2(/*this*/);
			shader = new hxsl.DynamicShader(shaderGraphDef.shader);
			for (init in shaderGraphDef.inits) {
				setParamValue(init.variable, init.value, shader);
			}
			for (m in cube.getMaterials()) {
				m.mainPass.addShader(shader);
			}
			currentShaderPreview = shader;
			currentShaderDef = shaderGraphDef;
		} catch(e : Dynamic) {
			if (shader != null) {
				for (m in cube.getMaterials()) {
					m.mainPass.removeShader(shader);
				}
			}
		}
	}

	public function setParamValueByName(varName : String, value : Dynamic) {
		if (currentShaderDef == null) return;
		for (init in currentShaderDef.inits) {
			if (init.variable.name == varName) {
				setParamValue(init.variable, value, currentShaderPreview);
				return;
			}
		}
	}

	public function setParamValue(variable : TVar, value : Dynamic, shader : hxsl.DynamicShader) {
		scene.setCurrent();
		try {
			switch (variable.type) {
				case TSampler2D:
					shader.setParamValue(variable, scene.loadTexture("", value));
				case TVec(size, _):
					shader.setParamValue(variable, h3d.Vector.fromArray(value));
				default:
					shader.setParamValue(variable, value);
			}
		} catch (e : Dynamic) {
			// variable not used
		}
	}

	#end
}