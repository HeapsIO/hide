package hrt.prefab.fx;

typedef EventInstance = {
	evt: Event,
	?play: Void->Void,
	?setTime: Float->Void
};

class Event extends hrt.prefab.Prefab {
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

	public static function updateEvents(evts: Array<EventInstance>, time: Float, prevTime: Float) {
		if(evts == null) return;

		for(evt in evts) {
			if(evt.play != null && time > prevTime && time < time)
				evt.play();

			if(evt.setTime != null)
				evt.setTime(time - evt.evt.time);
		}
	}

	#if editor
	public function getDisplayInfo(ctx: EditContext) : { label: String, length: Float } {
		throw "Not implemented";
	}
	#end
}