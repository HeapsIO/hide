package hrt.prefab.fx;

@:prefabIcon(HuiRes.ui.icons.prefab.gradient)
class Gradient extends Prefab {
	@:s public var data : hrt.impl.Gradient.GradientData = hrt.impl.Gradient.getDefaultGradientData();

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	public function getColor(time: Float, ?out: h3d.Vector4) : h3d.Vector4 {
		return hrt.impl.Gradient.evalData(data, time, out);
	}

	public function makeVal() : Value {
		var g = new hrt.impl.Gradient();
		g.data = data;
		return VGradient(g);
	}

	public static function getGradient(parent: Prefab, name: String, onlyEnabled=true) : Gradient {
		var lowerName = name.toLowerCase();
		for (c in parent.children) {
			if (onlyEnabled && !c.enabled)
				continue;
			#if editor
			if (parent.shared.editor?.isHidden(c))
				continue;
			#end
			var g = Std.downcast(c, Gradient);
			if (g != null && g.name?.toLowerCase() == lowerName)
				return g;
		}
		return null;
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {
		super.edit2(ctx);
		ctx.build(
			<category("Parameters")>
				<gradient label="Gradient" field={data}/>
			</category>
		);
	}

	#if editor
	override function edit(ctx: hide.prefab.EditContext) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element('<div class="group" name="Parameters">
			<dl>
				<dt>Gradient</dt><dd><input type="gradient" field="data"/></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "eyedropper", name : "Gradient", allowParent : FX.inFX, allowChildren : _ -> false };
	}
	#end

	static var _ = Prefab.register("fxgradient", Gradient);
}
