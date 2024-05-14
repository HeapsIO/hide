package hrt.shgraph;

import Type as HaxeType;
using hxsl.Ast;

import h3d.scene.Mesh;

using Lambda;
using hrt.shgraph.Utils;
import hrt.shgraph.AstTools.*;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.SgHxslVar.ShaderDefInput;

#if editor
import hide.view.GraphInterface; 
#end


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

typedef InputInfo = {name: String, type: SgType, ?def: ShaderDefInput};
typedef OutputInfo = {name: String, type: SgType};
typedef VariableDecl = {v: TVar, display: String, ?vertexOnly: Bool};
typedef AliasInfo = {?nameSearch: String, ?nameOverride : String, ?description : String, ?args : Array<Dynamic>, ?group: String};
@:autoBuild(hrt.shgraph.Macros.autoRegisterNode())
@:keepSub
@:keep
class ShaderNode 
#if editor
implements hide.view.GraphInterface.IGraphNode 
#end
{

	public var id : Int;
	public var x : Float;
	public var y : Float;
	public var showPreview : Bool = true;
	@prop public var nameOverride : String;


	#if editor
	// IGraphNode Interface
	public function getInfo() : GraphNodeInfo {
		var metas = haxe.rtti.Meta.getType(HaxeType.getClass(this));
		return {
			name: nameOverride ?? (metas.name != null ? metas.name[0] : "undefined"),
			inputs: [
				for (i in getInputs()) {
					var defaultParam = null;
					switch (i.def) {
						case Const(intialValue):
							defaultParam = {
								get: () -> Std.string(Reflect.getProperty(defaults, i.name) ?? intialValue),
								set: (s:String) -> Reflect.setField(defaults, i.name, Std.parseFloat(s)),
							};
						default:
					}
					{
						name: i.name,
						color: 0xFF0000,
						defaultParam: defaultParam,
					}
				}
			],
			outputs: [
				for (o in getOutputs()) {
					{
						name: o.name,
						color: 0xFF0000,
					}
				}
			],
			preview: {
				getVisible: () -> showPreview,
				setVisible: (b:Bool) -> showPreview = b,
				fullSize: false,
			},
		};
	}

	public function getId() : Int {
		return id;
	}

	public function getPos(p : h2d.col.Point) : Void {
		p.set(x,y);
	}

	public function setPos(p : h2d.col.Point) : Void {
		x = p.x;
		y = p.y;
	}

	public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		return [];
	}
	#end

	public function serializeToDynamic() : Dynamic {
		return {
			x: x,
			y: y,
			id: id,
			type: std.Type.getClassName(std.Type.getClass(this)),
			properties: saveProperties(),
		};
	}

	public static function createFromDynamic(data: Dynamic) : ShaderNode {
		var type = std.Type.resolveClass(data.type);
		var inst = std.Type.createInstance(type, []);
		inst.x = data.x;
		inst.y = data.y;
		inst.id = data.id;
		inst.connections = [];
		inst.loadProperties(data.properties);
		return inst;
	}

	public var defaults : Dynamic = {};

	/**
		Declare all the inputs this node uses
	**/
	public function getInputs() : Array<InputInfo> {
		return [];
	}

	/**
		Declare all the outputs this node uses
	**/
	public function getOutputs() : Array<OutputInfo> {
		return [];
	}

	/**
		Generate the hxsl expressions and outputs of the node
	**/
	public function generate(ctx: NodeGenContext) : Void {
		throw "generate is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
	}

	function getDef(name: String, def: Float) {
		var defaultValue = Reflect.getProperty(defaults, name);
		if (defaultValue != null) {
			def = Std.parseFloat(defaultValue) ?? def;
		}
		return def;
	}

	public function getAliases(name: String, group: String, description: String) : Array<AliasInfo> {
		var cl = HaxeType.getClass(this);
		var meta = haxe.rtti.Meta.getType(cl);
		var aliases : Array<AliasInfo> = [];

		if (meta.alias != null) {
			for (a in meta.alias) {
				aliases.push({nameOverride: '$a'});
			}
		}
		return aliases;
	}
	public var connections : Array<ShaderGraph.Connection> = [];

	public function setId(id : Int) {
		this.id = id;
	}

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		showPreview = props.showPreview ?? true;
		nameOverride = props.nameOverride;

		for (f in fields) {
			if (f == "defaults") {
				defaults = Reflect.field(props, f);
			}
			else {
				if (Reflect.hasField(this, f)) {
					Reflect.setField(this, f, Reflect.field(props, f));
				}
			}
		}
	}

	final public function shouldShowPreview() : Bool {
		return showPreview && canHavePreview();
	}

	public function canHavePreview() : Bool {
		return true;
	}

	public function saveProperties() : Dynamic {
		var parameters : Dynamic = {};

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

		parameters.nameOverride = nameOverride;
		parameters.showPreview = showPreview;

		return parameters;
	}

	#if editor
	final public function getHTML(width: Float, config: hide.Config) {
		var props = getPropertiesHTML(width);
		return props;
	}

	static public var registeredNodes = new Map<String, Class<ShaderNode>>();

	static public function register(key : String, cl : Class<ShaderNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}
	#end

}