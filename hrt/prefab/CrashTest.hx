package hrt.prefab;

/**
	Editor debug only prefab that allow to test various crash situations in the editor
	Should never be loaded in a game
**/
class CrashTest extends hrt.prefab.Object3D {
	@:s public var crashOnLoad: Bool = false;
	@:s public var crashOnInspector: Bool = false;
	@:s public var crashOnMake: Bool = false;
	@:s public var crashOnSync: Bool = false;

	override public function load(data) {
		super.load(data);
		if (crashOnLoad) {
			throw "CrashTest crashOnLoad";
		}
	}

	override public function copy(p) {
		super.copy(p);
	}

	override public function makeObject(parent3d:h3d.scene.Object) : h3d.scene.Object {
		if (crashOnMake) {
			throw "CrastTest crashOnMake";
		}

		return new CrashTestObject(this, parent3d);
	}

	override function edit2(ctx) {
		super.edit2(ctx);

		ctx.build(
			<category("Crash Test")>
				<checkbox field={crashOnLoad}/>
				<checkbox field={crashOnInspector}/>
				<checkbox field={crashOnMake}/>
				<checkbox field={crashOnSync}/>
			</category>
		);

		if(crashOnInspector) {
			throw "CrashTest crashOnInspector";
		}
	}

	static var _ = Prefab.register("crashTest", CrashTest);
}

class CrashTestObject extends h3d.scene.Object {
	var prefab : CrashTest;

	public function new(prefab: CrashTest, ?parent: h3d.scene.Object) {
		super(parent);
		this.prefab = prefab;
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		super.sync(ctx);
		if (prefab.crashOnSync) {
			throw "CrasTest crashOnSync";
		}
	}
}