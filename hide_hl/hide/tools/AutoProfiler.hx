package hide.tools;

class AutoProfiler {

	public var scriptPath : String = ".vscode\\post_profile.bat";
	public var outputDir : String = null;
	public var dtThreshold : Float = 0.1;
	public var contextFrameCount : Int = 3;
	public var cooldownFrameCount : Int = 10;
	public var lastFrame : Float = 0.0;

	// Internal
	var curContextFrame : Int = -1;
	var curCooldownFrame : Int = -1;
	var eventCount = 0;

	public function new() {
	}

	public function start(samplePerSeconds : String = "5000") {
		hl.Profile.event(-7, samplePerSeconds);
		hl.Profile.event(-3);
		hl.Profile.event(-5);
		eventCount = 0;
		lastFrame = haxe.Timer.stamp();
	}

	public function pause() {
		hl.Profile.event(-4);
	}

	public function resume() {
		hl.Profile.event(-5);
	}

	public function clear() {
		pause();
		hl.Profile.event(-3);
		resume();
	}

	public function dump( ?path : String ) {
		if( path == null ) {
			var baseDir = outputDir == null ? "" : outputDir + "/";
			if (  outputDir != null && !sys.FileSystem.exists(baseDir) )
				sys.FileSystem.createDirectory(baseDir);
			path = baseDir + "autocapture_" + DateTools.format(Date.now(), "%Y_%m_%d_%H_%M_%S") + ".dump";
		}
		hl.Profile.event(-6, path); // save dump
		if( Sys.command(scriptPath + " " + path) != 0 )
			throw "Could not post process profile dump : missing profiler.hl compilation?";
		hl.Profile.event(-4); // pause all
		hl.Profile.event(-3); // clear data
		return path;
	}

	public function beginFrame() {
		var dt = haxe.Timer.stamp() - lastFrame;
		if ( curContextFrame >= 0 ) {
			curContextFrame++;
			if ( curContextFrame >= contextFrameCount ) {
				dump();
				curContextFrame = -1;
				curCooldownFrame = 0;
			}
		} else if ( curCooldownFrame >= 0 )  {
			curCooldownFrame++;
			if ( curCooldownFrame >= cooldownFrameCount) {
				start();
				curCooldownFrame = -1;
			}
		} else if ( dt >= dtThreshold ) {
			curContextFrame = 0;
		} else
			clear();

		if ( curCooldownFrame == -1)
			hl.Profile.event(0);
		lastFrame = haxe.Timer.stamp();
	}

	public function insertEvent( eventName : String ) {
		hl.Profile.event(++eventCount, eventName);
	}
}