package hrt.shgraph.nodes;

import h3d.scene.Mesh;
import hide.Config;
using hxsl.Ast;

@name("Preview")
@description("Preview node, just to debug :)")
@group("Output")
@width(100)
class Preview extends ShaderNode {

	@input("input") var input = SType.Vec4;

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
	static var availableOutputs = [];

	#if editor
	public var shaderGraph : ShaderGraph;
	var cube : Mesh;
	var scene : hide.comp.Scene;
	var saveShader : hxsl.DynamicShader;
	public var config : Config;

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
		var element = new hide.Element('<div style="width: 100px; height: 90px"><div class="preview-parent" ><div class="node-preview" style="height: 100px" ></div></div></div>');

		scene = new hide.comp.Scene(config, null, element.find(".node-preview"));
		scene.onReady = function() {
			//new h3d.scene.CameraController(scene.s3d).loadFromCamera();
			var prim = new h3d.prim.Cube();
			prim.addUVs();
			prim.addNormals();
			cube = new Mesh(prim, scene.s3d);
			scene.init();
			element.find(".node-preview").removeClass("hide-scene-container");
			scene.resetCamera(cube);
			onMove();
			computeOutputs();
		};

		elements.push(element);
		return elements;
	}

	public function onMove(?x : Float, ?y : Float, zoom : Float = 1.) {
		var top : Float;
		var left : Float;
		var preview = new hide.Element(".node-preview");
		var parent = preview.parent();
		if (x != null && y != null) {
			left = x;
			top = y + 17;
		} else {
			var offsetWindow = preview.closest(".heaps-scene").offset();
			var offset = preview.closest("foreignObject").offset();
			top = offset.top - offsetWindow.top - 15;
			left = offset.left - offsetWindow.left;
		}
		parent.css("top", top/(zoom*1.001));
		parent.css("left", left/zoom);
		parent.css("zoom", zoom);
	}

	function onResize() {
		if( cube == null ) return;

	}

	override public function computeOutputs() {
		if (saveShader != null) {
			for (m in cube.getMaterials()) {
				m.mainPass.removeShader(saveShader);
			}
		}

		if (scene == null || input == null || input.isEmpty()) return;

		scene.setCurrent();
		var shaderGraphDef = shaderGraph.compile(this);
		var shader = new hxsl.DynamicShader(shaderGraphDef.shader);
		for (init in shaderGraphDef.inits) {
			var variable = init.variable;
			var value : Dynamic = init.value;
			switch (variable.type) {
				case TSampler2D:
					shader.setParamValue(variable, scene.loadTexture("", value));
				default:
					if (variable.name.toLowerCase().indexOf("color") != -1) {
						shader.setParamValue(variable, h3d.Vector.fromArray(value));
					} else {
						shader.setParamValue(variable, value);
					}
			}
		}
		for (m in cube.getMaterials()) {
			m.mainPass.addShader(shader);
		}
		saveShader = shader;
	}

	#end
}