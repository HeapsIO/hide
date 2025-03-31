package hrt.prefab.fx;

typedef EventInstance = {
	evt: IEvent,
	?play: Void->Void,
	?stop: Void->Void,
	?setTime: Float->Void,
	?playing: Bool,
};

interface IEvent {
	var name : String;
	var time(default, set) : Float;
	var hidden : Bool;
	var lock : Bool;
	var selected : Bool;
	function getEventPrefab() : hrt.prefab.Prefab;
	function getDuration() : Float;
	#if editor
	function setDuration(duration: Float) : Void;
	function getDisplayInfo(ctx: hide.prefab.EditContext) : { label: String, ?loop: Bool };
	#end
}

class Event extends hrt.prefab.Prefab implements IEvent {
	@:s public var time(default, set): Float = 0.0;
	@:s public var duration: Float = 0.0;
	public var hidden:Bool = false;
	public var lock:Bool = false;
	public var selected:Bool = false;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	function set_time(v) {
		return time = v;
	}

	public function getDuration() {
		return duration;
	}

	public function prepare() : EventInstance {
		return {
			evt: this
		};
	}

	public static function updateEvents(evts: Array<EventInstance>, time: Float, prevTime: Float, duration: Float) {
		if(evts == null) return;

		for(evt in evts) {
			var start = evt.evt.time;
			var end = evt.evt.getDuration() + start;

			// Take "looping" and seeking back in time into account
			if (time < prevTime && duration > 0) {
				prevTime -= duration;
			}

			if (time > prevTime) {
				var shouldBePlaying = start <= time && end > prevTime;

				if (!evt.playing && shouldBePlaying) {
					evt.playing = true;
					if (evt.play != null)
						evt.play();
				}

				if (evt.playing && (!shouldBePlaying || end <= time)) {
					evt.playing = false;
					if (evt.stop != null)
						evt.stop();
				}
			}


			if(evt.setTime != null)
				evt.setTime(time - evt.evt.time);
		}
	}

	public static function stopAllEvents(evts: Array<EventInstance>) {
		if (evts == null)
			return;

		for (evt in evts) {
			if (evt.playing) {
				evt.playing = false;
				if (evt.stop != null)
					evt.stop();
			}
		}
	}

	public function getEventPrefab() { return this; }

	#if editor

	override function edit( ctx ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
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
			loop: false
		};
	}

	public function canEditDuration() : Bool {
		return true;
	};

	public function setDuration(duration: Float) {
		this.duration = duration;
	};

	#end

	static var _ = Prefab.register("event", Event);
}

class Event3D extends hrt.prefab.Object3D implements IEvent {
	@:s public var time(default, set): Float = 0.0;
	@:s public var duration: Float = 0.0;
	public var hidden:Bool = false;
	public var lock:Bool = false;
	public var selected:Bool = false;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	function set_time(v) {
		return time = v;
	}

	public function getDuration() {
		return duration;
	}

	public function prepare() : EventInstance {
		return {
			evt: this
		};
	}

	public function getEventPrefab() { return this; }

	#if editor

	override function edit( ctx ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "bookmark", name : "Event3D",
		};
	}

	public function getDisplayInfo(ctx: hide.prefab.EditContext) {
		return {
			label: name,
			loop: false
		};
	}

	public function canEditDuration() : Bool {
		return true;
	};

	public function setDuration(duration: Float) {
		this.duration = duration;
	};

	#end

	static var _ = Prefab.register("event3d", Event3D);
}
