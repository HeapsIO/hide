package hide.tools;

import hxd.res.TextureStream;

/**
	What HIDE was doing before a crash, written in the crash reports : the last editor actions,
	the open views and the GPU state (also logged in gpu.log of the session logs).
**/
class CrashReport {

	static var MAX_ACTIONS = 100;
	static var actions : Array<String> = [];
	static var startTime = Date.now();

	/** an editor action : the last MAX_ACTIONS are kept **/
	public static function log( action : String ) {
		if( actions.length >= MAX_ACTIONS ) actions.shift();
		actions.push(DateTools.format(Date.now(), "%H:%M:%S") + " " + action);
	}

	/** logs the GPU state every minute **/
	public static function startGpuLog() {
		var timer = new haxe.Timer(60000);
		timer.run = () -> logGpu(null);
	}

	public static function logGpu( event : String ) {
		var dir = Sys.getEnv("HIDE_SESSION_LOGS");
		if( dir == null ) return;
		var line = DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S") + (event == null ? "" : " " + event + " :") + " " + getGpuState().join(" | ") + "\n";
		try js.node.Fs.appendFileSync(js.node.Path.join(dir, "gpu.log"), line) catch( e : Dynamic ) {}
	}

	static function getGpuState() : Array<String> {
		function mb( v : Float ) return Std.int(v / 1048576) + " MB";
		var out = [];
		#if dx12
		out.push("DX12 device " + js.Syntax.code("typeof __dx12.js_device_state == 'function' ? __dx12.js_device_state() : 'unknown (old addon)'"));
		#end
		try {
			var engine = h3d.Engine.getCurrent();
			if( engine != null ) {
				var mem = engine.driver.getMemoryUsage();
				if( mem != null ) out.push("VRAM " + mb(mem.allocated) + " / " + mb(mem.total) + " budget");
				var s = engine.mem.stats();
				out.push('current engine ${s.textureCount} textures ${mb(s.textureMemory)}, ${s.bufferCount} buffers ${mb(s.bufferMemory)}');
			}
		} catch( e : Dynamic )
			out.push("memory error " + e);
		var budget = TextureStream.getBudget();
		out.push('texture streaming ${TextureStream.ENABLED ? "on" : "off"}, resident ${mb(TextureStream.residentBytes)}, excess ${mb(TextureStream.excessBytes)}, budget ${budget < 0 ? "none" : mb(budget)}, max visible size ${TextureStream.maxVisibleSize}');
		return out;
	}

	/** the text of info.txt **/
	public static function getInfo() {
		function exec( cmd : String ) : String {
			return try (js.node.ChildProcess.execSync(cmd) : Dynamic).toString() catch( e : Dynamic ) "?";
		}

		var ide = Ide.inst;
		var buf = new StringBuf();
		var driver = #if dx12 "dx12" #else "webgl" #end;
		var build = Ide.getGitCommitHashAndDate();
		buf.add('hide $driver $build\n');
		// the commit of the local changes
		if( build == "dev" )
			buf.add("HEAD " + exec('git log --pretty=format:"%h(%cs)" -n 1') + "\n" + exec("git status --porcelain=v1"));
		buf.add('Project : ${@:privateAccess ide.currentProject}\n');

		var up = Std.int((Date.now().getTime() - startTime.getTime()) / 1000);
		buf.add('Page loaded at ${DateTools.format(startTime, "%H:%M:%S")} (${Std.int(up / 3600)}h ${Std.int(up / 60) % 60}m ${up % 60}s ago)\n');

		buf.add("\nViews (> focused, * visible) :\n");
		var focus = js.Browser.document.activeElement;
		for( v in @:privateAccess ide.views ) {
			var el = v.element == null ? null : v.element.get(0);
			var mark = (el != null && el.contains(focus) ? ">" : " ") + (v.isActive() ? "*" : " ");
			buf.add('$mark $v\n');
		}

		buf.add("\nGPU :\n" + getGpuState().join("\n") + "\n");
		buf.add("\nLast actions :\n" + actions.join("\n") + "\n");
		return buf.toString();
	}
}
