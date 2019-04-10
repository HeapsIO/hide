package hrt.shgraph.nodes;

import hide.Element;
using hxsl.Ast;

@name("Color")
@description("Color input, it's static")
@group("Input")
@width(100)
class Color extends ShaderNode {

	@output() var output = SType.Vec4;

	@prop() var r : Float = 0;
	@prop() var g : Float = 0;
	@prop() var b : Float = 0;
	@prop() var a : Float = 1;

	override public function computeOutputs() {
		addOutput("output", TVec(4, VFloat));
	}

	override public function build(key : String) : TExpr {

		return { e: TBinop(OpAssign, {
						e: TVar(output),
						p: null,
						t: output.type
					}, {
						e: TCall({
							e: TGlobal(Vec4),
							p: null,
							t: TFun([
								{
									ret: output.type,
									args: [
									{ name: "r", type : TFloat },
									{ name: "g", type : TFloat },
									{ name: "b", type : TFloat },
									{ name: "a", type : TFloat }]
								}
							])
						}, [{
								e: TConst(CFloat(r)),
								p: null,
								t: TFloat
							},
							{
								e: TConst(CFloat(g)),
								p: null,
								t: TFloat
							},
							{
								e: TConst(CFloat(b)),
								p: null,
								t: TFloat
							},{
								e: TConst(CFloat(a)),
								p: null,
								t: TFloat
							}]),
						p: null,
						t: output.type
					}),
					p: null,
					t: output.type
				};
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new Element('<div style="width: 47px; height: 35px"></div>');
		var picker = new hide.comp.ColorPicker(true, element);


		var start = h3d.Vector.fromArray([r, g, b, a]);
		picker.value = start.toColor();

		picker.onChange = function(move) {
			var vec = h3d.Vector.fromColor(picker.value);
			r = vec.x;
			g = vec.y;
			b = vec.z;
			a = vec.w;
		};

		elements.push(element);

		return elements;
	}
	#end

}