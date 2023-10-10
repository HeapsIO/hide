package hrt.shgraph.nodes;

import h3d.scene.Mesh;

using hxsl.Ast;


class AlphaPreview extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		var screenUV : Vec2;
		function fragment() {
			var gray_lt = vec3(1.0);
			var gray_dk = vec3(229.0) / 255.0;
			var scale = 16.0;
			var localUV = screenUV * scale;

			var checkboard = floor(localUV.x) + floor(localUV.y);
			checkboard = fract(checkboard * 0.5) * 2.0;
			var alphaColor = vec3(checkboard * (gray_dk - gray_lt) + gray_lt);

			pixelColor.rgb = mix(pixelColor.rgb, alphaColor, 1.0 - pixelColor.a);
			pixelColor.a = 1.0;
		}
	}
}

@name("Preview")
@description("Preview node, just to debug :)")
@group("Output")
@width(100)
@noheader()
class Preview extends ShaderNode {

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = {name: "input", id: getNewIdFn(), type: TVec(4, VFloat), kind: Param, qualifiers: []};
		var output : TVar = {name: "pixelColor", id: getNewIdFn(), type: TVec(4, VFloat), kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		//var param = getParameter(inputNode.parameterId);
		//inits.push({variable: inVar, value: param.defaultValue});

		return {expr: finalExpr, inVars: [{v: inVar, internal: false, isDynamic: false}], outVars:[], externVars: [output], inits: []};
	}

	// @input("Input") var input = SType.Vec4;

	// public var variable : TVar;

	// override public function build(key : String) : TExpr {

	// 	return {
	// 			p : null,
	// 			t : TVoid,
	// 			e : TBinop(OpAssign, {
	// 				e: TVar(variable),
	// 				p: null,
	// 				t: variable.type
	// 			}, input.getVar(variable.type))
	// 		};

	// }

	#if editor
	var nodePreview : js.jquery.JQuery;
	var element : js.jquery.JQuery;
	public var shaderGraph: ShaderGraph;
	var cube : Mesh;
	var scene : hide.comp.Scene;
	var currentShaderPreview : hxsl.DynamicShader;
	var alphaPreview : AlphaPreview = null;
	var currentShaderDef : hrt.prefab.ContextShared.ShaderDef;
	var inited = false;
	public var config : hide.Config;

	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);

		if (element == null) {
			element = new hide.Element('<div style="width: 100px; height: 100px"><div class="preview-parent" top="-10px" ><div class="node-preview" style="height: 100px" ></div></div></div>');
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
				inited = true;

				update();
			};
		}

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

	public function update() {
		if (!inited)
			return;
		if (currentShaderPreview != null) {
			for (m in cube.getMaterials()) {
				m.mainPass.removeShader(currentShaderPreview);
			}
			currentShaderPreview = null;
		}

		if (@:privateAccess scene.window == null)
			return;
		scene.setCurrent();

		if (alphaPreview == null)
			alphaPreview = new AlphaPreview();

		var shader : hxsl.DynamicShader = null;
		try {
			var shaderGraphDef = shaderGraph.compile2(this);
			shader = new hxsl.DynamicShader(shaderGraphDef.shader);
			for (init in shaderGraphDef.inits) {
				setParamValue(init.variable, init.value, shader);
			}
			for (m in cube.getMaterials()) {
				m.mainPass.addShader(shader);
				m.mainPass.addShader(alphaPreview);
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