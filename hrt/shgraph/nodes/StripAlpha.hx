package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Strip Alpha")
@description("Separate the rgb and a components of an rgba vector")
@group("Channel")
class StripAlpha extends ShaderNode {

	@input("RGBA") var input = SType.Vec4;

	@output("RGB") var rgb = SType.Vec3;
	@output("A") var a = SType.Float;

	override public function computeOutputs() {
		addOutput("rgb", TVec(3, VFloat));
		addOutput("a", TFloat);
	}

	override public function build(key : String) : TExpr {
        if( key == "a" ) {
            return { e: TBinop(OpAssign, {
                    e: TVar(getOutput(key)),
                    p: null,
                    t: getOutput(key).type
                }, {
                    e: TSwiz(input.getVar(TVec(4, VFloat)), [W]),
                    p: null,
                    t: getOutput(key).type
                }),
                p: null,
                t: getOutput(key).type
            };
	    }
        return { e: TBinop(OpAssign, {
                e: TVar(getOutput(key)),
                p: null,
                t: getOutput(key).type
            }, {
                e: TSwiz(input.getVar(TVec(4, VFloat)), [X, Y, Z]),
                p: null,
                t: getOutput(key).type
            }),
            p: null,
            t: getOutput(key).type
        };
    }

}