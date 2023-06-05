package hrt.prefab.fx;

typedef EventInstance = {
	evt: Event,
	?play: Void->Void,
	?setTime: Float->Void
};

interface IEvent {
	#if editor
	function getEventPrefab() : hrt.prefab.Prefab;
	function getDisplayInfo(ctx: hide.prefab.EditContext) : { label: String, length: Float, ?loop: Bool };
	#end
	var time(default, set) : Float;
}

class Event extends hrt.prefab.Prefab implements IEvent {
	@:s public var time(default, set): Float = 0.0;


	public function new(?parent, shared: ContextShared) {
		super(parent, shared);
	}

	function set_time(v) {
		return time = v;
	}

	public function prepare() : EventInstance {
		return {
			evt: this
		};
	}

	public static function updateEvents(evts: Array<EventInstance>, time: Float, prevTime: Float) {
		if(evts == null) return;

		for(evt in evts) {
			if(evt.play != null && time > prevTime && evt.evt.time > prevTime && evt.evt.time <= time)
				evt.play();

			if(evt.setTime != null)
				evt.setTime(time - evt.evt.time);
		}
	}

	#if editor

	public function getEventPrefab() { return this; }

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

	public function getDisplayInfo(ctx: hide.prefab.EditContext) {
		return {
			label: name,
			length: 1.0,
			loop: false
		};
	}

	#end

	static var _ = Prefab.register("event", Event);
}