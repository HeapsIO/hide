package hrt.shgraph;

using hxsl.Ast;

import h3d.scene.Mesh;

using Lambda;

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

@:autoBuild(hrt.shgraph.Macros.autoRegisterNode())
@:keepSub
class ShaderNode {

	public var id : Int;
	public var previewEnabled = false;

	public var defaults : Dynamic = {};

	static var availableVariables = [
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "pixelColor",
						type: TVec(4, VFloat)
					}];


	public function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		throw "getShaderDef is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	public var connections : Map<String, ShaderGraph.Connection> = [];

	public var outputCompiled : Map<String, Bool> = []; // todo: put with outputs variable

	// TODO(ces) : caching
	public function getOutputs2(domain: ShaderGraph.Domain, ?inputTypes: Array<Type>) : Map<String, TVar> {
		var def = getShaderDef(domain, () -> 0);
		var map : Map<String, TVar> = [];
		for (tvar in def.outVars) {
			if (!tvar.internal)
				map.set(tvar.v.name, tvar.v);
		}
		return map;
	}

	// TODO(ces) : caching
	public function getInputs2(domain: ShaderGraph.Domain) : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput}> {
		var def = getShaderDef(domain, () -> 0);
		var map : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput}> = [];
		for (i => tvar in def.inVars) {
			if (!tvar.internal) {
				map.set(tvar.v.name, {v: tvar.v, def: tvar.defVal});
			}
		}
		return map;
	}


	public function setId(id : Int) {
		this.id = id;
	}


	function addOutput(key : String, t : Type) {
		/*outputs.set(key, { parent: null,
			id: 0,
			kind: Local,
			name: "output_" + id + "_" + key,
			type: t
		});*/
	}

	function removeOutput(key : String) {
		/*outputs.remove(key);*/
	}

	function addOutputTvar(tVar : TVar) {
		/*outputs.set(tVar.name, tVar);*/
	}

	public function computeOutputs() : Void {}

	// public function getOutput(key : String) : TVar {
	// 	return outputs.get(key);
	// }

	// public function getOutputType(key : String) : Type {
	// 	var output = getOutput(key);
	// 	if (output == null)
	// 		return null;
	// 	return output.type;
	// }

	// public function getOutputTExpr(key : String) : TExpr {
	// 	var o = getOutput(key);
	// 	if (o == null)
	// 		return null;
	// 	return {
	// 		e: TVar(o),
	// 		p: null,
	// 		t: o.type
	// 	};
	// }

	public function build(key : String) : TExpr {
		throw "Build function not implemented";
	}

	public function checkTypeAndCompatibilyInput(key : String, type : hxsl.Ast.Type) : Bool {
		/*var infoKey = getInputs2()[key].type;
		if (infoKey != null && !(ShaderType.checkConversion(type, infoKey))) {
			return false;
		}
		return checkValidityInput(key, type);*/
		return true;
	}

	public function checkValidityInput(key : String, type : hxsl.Ast.Type) : Bool {
		return true;
	}



	// public function getOutputInfoKeys() : Array<String> {
	// 	return [];
	// }

	// public function getOutputInfo(key : String) : OutputInfo {
	// 	return null;
	// }

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		for (f in fields) {
			if (f == "defaults") {
				defaults = Reflect.field(props, f);
			}
			else {
				Reflect.setField(this, f, Reflect.field(props, f));
			}
		}
	}

	public function saveProperties() : Dynamic {
		var parameters = {};

		var thisClass = std.Type.getClass(this);
		var fields = std.Type.getInstanceFields(thisClass);
		var metas = haxe.rtti.Meta.getFields(thisClass);
		var metaSuperClass = haxe.rtti.Meta.getFields(std.Type.getSuperClass(thisClass));

		for (f in fields) {
			var m = Reflect.field(metas, f);
			if (m == null) {
				m = Reflect.field(metaSuperClass, f);
				if (m == null)
					continue;
			}
			if (Reflect.hasField(m, "prop")) {
				var metaData : Array<String> = Reflect.field(m, "prop");
				if (metaData == null || metaData.length == 0 || metaData[0] != "macro") {
					Reflect.setField(parameters, f, Reflect.getProperty(this, f));
				}
			}
		}

		if (Reflect.fields(defaults).length > 0) {
			Reflect.setField(parameters, "defaults", defaults);
		}

		return parameters;
	}

	#if editor
	final public function getHTML(width: Float, config: hide.Config) {
		var props = getPropertiesHTML(width);
		//if (previewEnabled)
			props.push(getPreview(width, config));
		return props;
	}

	function getPropertiesHTML(width : Float) : Array<hide.Element> {
		return [];
	}

	static public var registeredNodes = new Map<String, Class<ShaderNode>>();

	static public function register(key : String, cl : Class<ShaderNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}
	#end

	#if editor
	var nodePreview : js.jquery.JQuery;
	var previewElement : js.jquery.JQuery;
	public var shaderGraph: ShaderGraph;
	var cube : Mesh;
	var scene : hide.comp.Scene;
	var shader : hxsl.DynamicShader;
	public var shaderGraphDef : hrt.prefab.ContextShared.ShaderDef = null;

	var alphaPreview : AlphaPreview = null;
	var inited = false;
	var config : hide.Config;

	public function getPreview(width : Float, config:  hide.Config) : hide.Element {
		this.config = config;
		if (previewElement == null) {
			previewElement = new hide.Element('<div style="width: ${width}px; height: ${width}px"><div class="preview-parent"><div class="node-preview" style="height: ${width}px; width: ${width}px;" ></div></div></div>');
			nodePreview = previewElement.find(".node-preview");

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

		return previewElement;
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
		if (shader != null) {
			for (m in cube.getMaterials()) {
				m.mainPass.removeShader(shader);
			}
			shader = null;
		}

		if (@:privateAccess scene.window == null)
			return;
		scene.setCurrent();

		if (alphaPreview == null)
			alphaPreview = new AlphaPreview();

		if (shaderGraphDef != null) {
			shader = new hxsl.DynamicShader(shaderGraphDef.shader);
			for (init in shaderGraphDef.inits) {
				setParamValue(init.variable, init.value, shader);
			}
			var select = shaderGraphDef.inits.find((v) -> v.variable.name == "__sg_PREVIEW_output_select");
			if (select != null) {
				setParamValue(select.variable, id + 1, shader);
			}
			for (m in cube.getMaterials()) {
				m.mainPass.addShader(shader);
				//m.mainPass.addShader(alphaPreview);
			}
		}
	}

	public function setParamValueByName(varName : String, value : Dynamic) {
		if (shaderGraphDef == null) return;
		for (init in shaderGraphDef.inits) {
			if (init.variable.name == varName) {
				setParamValue(init.variable, value, shader);
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