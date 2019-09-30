package hrt.prefab.fx;

typedef EventInstance = {
	evt: Event,
	?play: Void->Void,
	?setTime: Float->Void
};

class Event extends hrt.prefab.Prefab {
	public var time: Float = 0.0;

	public function new(?parent) {
		super(parent);
		this.type = "event";
	}

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
			if(evt.play != null && time > prevTime && evt.evt.time > prevTime && evt.evt.time < time)
				evt.play();

			if(evt.setTime != null)
				evt.setTime(time - evt.evt.time);
		}
	}

	#if editor

	override function edit( ctx ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "bookmark", name : "Event",
		};
	}

	public function getDisplayInfo(ctx) {
		return {
			label: name,
			length: 1.0
		};
	}

	#end

	static var _ = Library.register("event", Event);
}