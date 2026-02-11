package hide.tools;

class Profiler {
	public static var CLEAR_DATA = -3;
	public static var PAUSE_ALL = -4;
	public static var RESUME_ALL = -5;
	public static var SAVE_DUMP = -6;
    public static var SETUP = -7;

	public static var processing = false;

    public static function start() {
		processing = true;
		hl.Profile.event(Profiler.SETUP,"40000");
		hl.Profile.event(Profiler.CLEAR_DATA);
		hl.Profile.event(Profiler.RESUME_ALL);
	}

	public static function stop() {
		hl.Profile.event(Profiler.PAUSE_ALL);
		hl.Profile.event(Profiler.CLEAR_DATA);
	}

	public static function save() {
		hl.Profile.event(Profiler.SAVE_DUMP);
		processing = false;
	}
}