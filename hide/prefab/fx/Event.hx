package hide.prefab.fx;

typedef EventInstance = {
	evt: Event,
	play: Void->Void,
	setTime: Float->Void
};

class Event extends hxd.prefab.Prefab {
	public var time: Float = 0.0;

	override function save() : {} {
		return {
			time: time
		};
	}

	override function load(obj: Dynamic) {
		this.time = obj.time;
	}

	public function prepare(ctx: Context) : EventInstance {
		return null;
	}

	#if editor
	public function getDisplayInfo(ctx: EditContext) : { label: String, length: Float } {
		throw "Not implemented";
	}
	#end
}