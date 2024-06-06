package hrt.sbsgraph.nodes;

@name("Disc")
@description("Basic disc texture")
@width(80)
@group("Texture generation")
class Disc extends SubstanceNode {
	var inputs = [];
	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var out = h3d.mat.Texture.genDisc(outputWidth, 16777215, 1);
		return [ out ];
	}
}