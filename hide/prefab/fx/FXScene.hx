package hide.prefab.fx;
import hide.prefab.Curve;

typedef ObjectCurves = {
	?x: Curve,
	?y: Curve,
	?z: Curve,
	?rotationX: Curve,
	?rotationY: Curve,
	?rotationZ: Curve,
	?scaleX: Curve,
	?scaleY: Curve,
	?scaleZ: Curve,
	?visibility: Curve,
	?custom: Array<Curve>
}

class FXScene extends Library {

	public function new() {
		super();
		type = "fx";
	}

	override function save() {
		var obj : Dynamic = super.save();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var props = new hide.Element('
			<div class="group" name="Level">
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
		#end
	}

	override function getHideProps() {
		return { icon : "cube", name : "FX", fileSource : ["fx"] };
	}

	public function getCurves(element : hide.prefab.Prefab) : ObjectCurves {
		var ret : ObjectCurves = {};
		for(c in element.children) {
			var curve = c.to(Curve);
			if(curve == null)
				continue;
			switch(c.name) {
				case "position.x": ret.x = curve;
				case "position.y": ret.y = curve;
				case "position.z": ret.z = curve;
				case "rotation.x": ret.rotationX = curve;
				case "rotation.y": ret.rotationY = curve;
				case "rotation.z": ret.rotationZ = curve;
				case "scale.x": ret.scaleX = curve;
				case "scale.y": ret.scaleY = curve;
				case "scale.z": ret.scaleZ = curve;
				case "visibility": ret.visibility = curve;
				default: 
					if(ret.custom == null)
						ret.custom = [];
					ret.custom.push(curve);
			}
		}
		return ret;
	}

	public function getTransform(curves: ObjectCurves, time: Float, ?m: h3d.Matrix) {
		if(m == null)
			m = new h3d.Matrix();

		var x = curves.x == null ? 0. : curves.x.getVal(time);
		var y = curves.y == null ? 0. : curves.y.getVal(time);
		var z = curves.z == null ? 0. : curves.z.getVal(time);

		var rotationX = curves.rotationX == null ? 0. : curves.rotationX.getVal(time);
		var rotationY = curves.rotationY == null ? 0. : curves.rotationY.getVal(time);
		var rotationZ = curves.rotationZ == null ? 0. : curves.rotationZ.getVal(time);

		var scaleX = curves.scaleX == null ? 1. : curves.scaleX.getVal(time);
		var scaleY = curves.scaleY == null ? 1. : curves.scaleY.getVal(time);
		var scaleZ = curves.scaleZ == null ? 1. : curves.scaleZ.getVal(time);

		m.initScale(scaleX, scaleY, scaleZ);
		m.rotate(rotationX, rotationY, rotationZ);
		m.translate(x, y, z);

		return m;
	}

	static var _ = Library.register("fx", FXScene);
}