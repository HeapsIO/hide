package hrt.texgraph;

import Type as HaxeType;
import hrt.texgraph.TexGraph;
#if editor
import hide.view.GraphInterface;
#end

using Lambda;

typedef AliasInfo = { ?nameSearch: String, ?nameOverride : String, ?description : String, ?args : Array<Dynamic>, ?group: String };

@:autoBuild(hrt.texgraph.Macros.autoRegisterNode())
@:keepSub
@:keep
class TexNode
#if editor
implements hide.view.GraphInterface.IGraphNode
#end
{
	public static var registeredNodes = new Map<String, Class<TexNode>>();

	public var id : Int;
	public var connections : Array<TexGraph.Connection> = [];
	public var defaults : Dynamic = {};
	#if editor
	public var editor : hide.view.GraphEditor;
	#end
	public var x : Float;
	public var y : Float;
	public var showPreview : Bool = true;
	@prop public var nameOverride : String;

	// Base parameters that are overriding graph's parameters
	public var overrides = {};
	public var outputHeight = 256;
	public var outputWidth = 256;
	public var outputFormat = hxd.PixelFormat.RGBA;


	var ctx(get, null) : h3d.impl.RenderContext;
	function get_ctx() {
		#if editor
		var s2d = editor.previewsScene.s2d;
		return @:privateAccess s2d.ctx;
		#else
		return null;
		#end
	}

	static public function register(key : String, cl : Class<TexNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}

	#if editor
	public function getInfo() : GraphNodeInfo {
		var metas = haxe.rtti.Meta.getType(HaxeType.getClass(this));
		return {
			name: nameOverride ?? (metas.name != null ? metas.name[0] : "undefined"),
			inputs: [
				for (i in getInputs()) {
					{
						name: i.name,
						color: TexNode.getTypeColor(i.type),
					}
				}
			],
			outputs: [
				for (o in getOutputs()) {
					{
						name: o.name,
						color: TexNode.getTypeColor(o.type),
					}
				}
			],
			preview: {
				getVisible: () -> showPreview,
				setVisible: (b:Bool) -> showPreview = b,
				fullSize: false,
			},
			width: metas.width != null ? metas.width[0] : null,
			noHeader: Reflect.hasField(metas, "noheader"),
		};
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

	public static function createFromDynamic(data: Dynamic, graph: TexGraph) : TexNode {
		var type = std.Type.resolveClass(data.type);
		var inst = std.Type.createInstance(type, []);
		inst.x = data.x;
		inst.y = data.y;
		inst.id = data.id;
		inst.connections = [];
		inst.loadProperties(data.properties);
		return inst;
	}

	static function getTypeColor(type : Dynamic ) : Int {
		return switch (type) {
			case h3d.mat.Texture:
				0xffaf41;
			default:
				0xc8c8c8;
		}
	}

	public function serializeToDynamic() : Dynamic {
		return {
			x: x,
			y: y,
			id: id,
			type: std.Type.getClassName(std.Type.getClass(this)),
			properties: saveProperties(),
		};
	}

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		showPreview = props.showPreview ?? true;
		nameOverride = props.nameOverride;
		overrides = props.overrides != null ? props.overrides : {};

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
		parameters.overrides = overrides;

		return parameters;
	}

	public function getInputs() : Array<Dynamic> {
		return Reflect.field(this, "inputs")??[];
	}

	public function getOutputs() : Array<Dynamic> {
		return Reflect.field(this, "outputs")??[];
	}

	public function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		return [];
	}

	public function getInputData(vars : Dynamic, inputIdx : Int) : Dynamic {
		if (connections.length <= inputIdx || connections[inputIdx] == null)
			return getDefaultInputData(inputIdx);

		var outputs = vars.get(connections[inputIdx].from.id);
		if (outputs == null || outputs.length <= connections[inputIdx].outputId)
			return getDefaultInputData(inputIdx);

		return vars.get(connections[inputIdx].from.id)[connections[inputIdx].outputId];
	}

	#if editor
	public function getSpecificParametersHTML() : hide.Element {
		return null;
	}
	#end

	function getDefaultInputData(inputIdx : Int) {
		var input = getInputs()[inputIdx];

		switch (input.type) {
			case h3d.mat.Texture:
				return new h3d.mat.Texture(1, 1);
			default:
				return null;
		}
	}

	function createTexture() : h3d.mat.Texture {
		var tex = new h3d.mat.Texture(outputWidth, outputHeight, [Target], outputFormat);
		tex.clear(0);
		return tex;
	}
}