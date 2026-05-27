package hrt.ui;

#if hui
class HuiLodLine extends HuiElement {
	static var SRC = <hui-lod-line>
		<hui-element id="areas">
		</hui-element>
		<hui-element id="cursor">
			<hui-element id="bar"></hui-element>
			<hui-text("X%") id="label"></hui-text>
		</hui-element>
	</hui-lod-line>

	public static var AREA_COLORS = [ 0xfff3e179 , 0xff79f37b, 0xff8979f3, 0xfff379ad ];
	public var mesh(default, set) : h3d.scene.Mesh;
	public function set_mesh(v) {
		hmd = Std.downcast(v.primitive, h3d.prim.HMDModel);
		mesh = v;
		maxLodRatio = hxd.Math.max(maxLodRatio, getLodRatio(0));
		createAreas();
		return mesh;
	}
	public var maxLodRatio = 1.;

	var currentScreenRatio : Float = 0;
	var hmd : h3d.prim.HMDModel;
	var areasEl : Array<{ a: HuiElement, ratio: HuiText }> = [];
	var handlesEl : Array<HuiElement> = [];
	var onDrag : (e : hxd.Event) -> Void;

	public function new(?parent: h2d.Object) {
		super(parent);

		initComponent();
		this.makeInteractive();
	}

	override function sync(ctx) {
		super.sync(ctx);

		if (hmd != null)
			moveCursorTo(@:privateAccess mesh.curScreenRatio);
	}

	override function onAfterReflow() {
		if (hmd != null) {
			moveCursorTo(@:privateAccess mesh.curScreenRatio);
			updateAreas();
		}
	}

	inline function isCulledLod(idx : Int) {
		return idx == hmd.lodCount();
	}

	inline function getLodRatio(idx : Int) {
		var lodConfig = hmd.getLodConfig();
		if (idx <= 0) return maxLodRatio;
		if (idx > lodConfig.length) return 0.;
		if (idx >= hmd.lodCount() + 1) return 0.;
		return lodConfig[idx - 1];
	}

	function createAreas() {
		areas.removeChildren();
		handlesEl = [];
		areasEl = [];

		for (idx in 0...hmd.lodCount() + 1) {
			var ratio = getLodRatio(idx);
			var a = new HuiElement(areas);
			a.dom.addClass("area");
			a.backgroundType = "hui";
			a.huiBg.background = AREA_COLORS[idx % AREA_COLORS.length];
			var aLabel = new HuiText(isCulledLod(idx) ? 'Culled' : 'LOD ${idx}', a);
			aLabel.dom.addClass("area-label");
			var aRatio = new HuiText('${hxd.Math.round(ratio * 100)}%', a);
			aRatio.dom.addClass("area-ratio");
			areasEl.push({ a: a, ratio: aRatio });

			if (idx != 0) {
				var h = new HuiElement(areas);
				h.dom.addClass("handle");
				handlesEl.push(h);
				var prevConfig : Array<Float>;
				var newConfig : Array<Float>;
				h.onPush = (e) -> {
					prevConfig = @:privateAccess hmd.lodConfig?.copy();
					newConfig = hmd.getLodConfig()?.copy();
					var limits = [ getLodRatio(idx + 1), getLodRatio(idx - 1)];
					areas.onMove = (e) -> {
						var newRatio = maxLodRatio - (e.relX / areas.calculatedWidth);
						if (Math.isNaN(newRatio))
							newRatio = 0;

						newRatio = hxd.Math.clamp(newRatio, limits[0], limits[1]);
						newConfig[idx - 1] = newRatio;
						@:privateAccess hmd.lodConfig = newConfig;
						updateAreas();
					};
				}

				h.onRelease = (e) -> {
					areas.onMove = (e) -> {};
					getView().undo.record((isUndo) -> {
						if (isUndo)
							@:privateAccess hmd.lodConfig = prevConfig;
						else
							@:privateAccess hmd.lodConfig = newConfig;
						updateAreas();
					}, true);
				}
			}
		}
	}

	function updateAreas() {
		for (idx in 0...hmd.lodCount() + 1) {
			var a = areasEl[idx];
			var ratio = getLodRatio(idx);
			var width = hxd.Math.floor((ratio / maxLodRatio) * areas.calculatedWidth);
			a.a.setWidth(width);
			a.a.setPosition(areas.calculatedWidth - width, a.a.y);
			a.ratio.text = '${hxd.Math.round((ratio * 10000)) / 100}%';
			if (idx != 0)
				handlesEl[idx - 1].setPosition(a.a.x - (handlesEl[idx - 1].calculatedWidth / 2), a.a.y);
		}
	}

	function moveCursorTo(f : Float) {
		f = hxd.Math.clamp(f, 0, maxLodRatio);
		currentScreenRatio = f;
		label.text = '${hxd.Math.round((currentScreenRatio * 10000)) / 100}%';
		var width = areas.calculatedWidth;
		cursor.setPosition(width * ((maxLodRatio - f) / maxLodRatio), cursor.y);
	}
}

#end