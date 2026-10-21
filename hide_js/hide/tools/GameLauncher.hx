package hide.tools;

enum State {
	Idle;
	Compiling;
	Running;
}

typedef GameTarget = {
	var hxml : String;
	var main : String;
	var output : String;
	var cwd : String;
}

class GameLauncher {
	static final GAME_LAUNCHER_HXML = "gameLauncher.hxml";

	public static var state(default, set) : State = Idle;
	public static dynamic function onStateChange() {}

	static var process : js.node.child_process.ChildProcess;
	static var target : GameTarget;
	static var stopRequested = false;

	static function set_state(v: State) {
		state = v;
		onStateChange();
		return v;
	}

	public static function toggle() {
		if (state == Idle)
			play();
		else
			stop();
	}

	static function play() {
		var target = try findTarget() catch (e) {
			hide.Ide.inst.quickError(e.message);
			return;
		}

		if (target == null) {
			hide.Ide.inst.quickError('No .hxml with both a -main and a -hl output found in ${hide.Ide.inst.projectDir}');
			return;
		}

		stopRequested = false;
		compile(target);
	}

	static function stop() {
		stopRequested = true;
		process.kill();
	}

	public static function listTargets() : Array<GameTarget> {
		var dir = hide.Ide.inst.projectDir;
		var files = sys.FileSystem.readDirectory(dir);
		files.sort(Reflect.compare);

		var targets = [];
		for (f in files) {
			if (haxe.io.Path.extension(f).toLowerCase() != "hxml")
				continue;
			var t = parseHxml(dir + "/" + f);
			if (t != null)
				targets.push(t);
		}
		return targets;
	}

	public static function getCurrentHxml() : Null<String> {
		var hxml : String = hide.Ide.inst.currentConfig.get(GAME_LAUNCHER_HXML);
		if (hxml == null)
			return listTargets()[0]?.hxml;
		return toAbsolutePath(hxml);
	}

	public static function getProjectHxml() : Null<String> {
		var hxml : String = hide.Ide.inst.projectConfig.get(GAME_LAUNCHER_HXML);
		return hxml != null ? toAbsolutePath(hxml) : null;
	}

	public static function setCurrentHxml(hxml: String) {
		hide.Ide.inst.projectUserConfig.set(GAME_LAUNCHER_HXML, hxml == getProjectHxml() ? null : toConfigPath(hxml));
	}

	static function toAbsolutePath(hxml: String) {
		return haxe.io.Path.normalize(haxe.io.Path.isAbsolute(hxml) ? hxml : hide.Ide.inst.projectDir + "/" + hxml);
	}

	static function toConfigPath(hxml: String) {
		var dir = hide.Ide.inst.projectDir + "/";
		hxml = hxml.split("\\").join("/");
		if (StringTools.startsWith(hxml.toLowerCase(), dir.toLowerCase()))
			hxml = hxml.substr(dir.length);
		return hxml;
	}

	static function findTarget() : Null<GameTarget> {
		var hxml = getCurrentHxml();
		if (hxml == null)
			return null;
		if (!sys.FileSystem.exists(hxml))
			throw '$hxml not found';
		var t = parseHxml(hxml);
		if (t == null)
			throw '$hxml doesn\'t declare both a -main and a -hl output';
		return t;
	}

	static function parseHxml(path: String) : Null<GameTarget> {
		path = haxe.io.Path.normalize(path);
		var main = null;
		var output = null;
		var cwd = haxe.io.Path.directory(path);

		for (line in readHxmlLines(path)) {
			var value = line[1];
			switch (line[0]) {
				case "-main", "--main", "-m":
					main = value;
				case "-hl", "--hl":
					output = value;
				case "--cwd", "-C":
					cwd = haxe.io.Path.isAbsolute(value) ? value : cwd + "/" + value;
				default:
			}
		}

		if (main == null || output == null)
			return null;

		cwd = haxe.io.Path.normalize(cwd);
		return {
			hxml: path,
			main: main,
			output: haxe.io.Path.isAbsolute(output) ? output : haxe.io.Path.normalize(cwd + "/" + output),
			cwd: cwd,
		};
	}

	static function readHxmlLines(file: String) : Array<Array<String>> {
		function unquote(s: String) {
			return s.length >= 2 && StringTools.startsWith(s, "\"") && StringTools.endsWith(s, "\"") ? s.substr(1, s.length - 2) : s;
		}

		var lines = [];
		for (line in sys.io.File.getContent(file).split("\n")) {
			line = StringTools.trim(line);
			if (line == "" || StringTools.startsWith(line, "#"))
				continue;
			var space = line.indexOf(" ");
			if (line.charCodeAt(0) == "-".code && space > 0)
				lines.push([line.substr(0, space), unquote(StringTools.trim(line.substr(space + 1)))]);
			else
				lines.push([unquote(line)]);
		}
		return lines;
	}

	static function compile(t: GameTarget) {
		target = t;
		var hxml = haxe.io.Path.withoutDirectory(target.hxml);

		hide.Ide.inst.quickMessage('Compiling ${target.main} ($hxml)');
		state = Compiling;
		start("haxe", [hxml], haxe.io.Path.directory(target.hxml), "haxe", (code, lines) -> {
			if (stopRequested) {
				hide.Ide.inst.quickMessage("Compilation cancelled");
				state = Idle;
			} else if (code != 0) {
				hide.Ide.inst.quickError('Compilation failed :\n${excerpt(lines, 8, true)}', 10);
				state = Idle;
			} else {
				run();
			}
		});
	}

	static function run() {
		state = Running;
		start("hl", [target.output], target.cwd, "game", (code, lines) -> {
			if (code != 0 && !stopRequested)
				hide.Ide.inst.quickError('Game exited with code $code\n${excerpt(lines, 8, false)}', 10);
			state = Idle;
		});
	}

	static function start(cmd: String, args: Array<String>, cwd: String, logPrefix: String, onExit: (code: Int, lines: Array<String>) -> Void) {
		var lines = [];
		function readPipe(input: js.node.stream.Readable.IReadable) {
			var pending = "";
			function addLine(line: String) {
				line = StringTools.rtrim(line);
				lines.push(line);
				js.Browser.console.log('[$logPrefix] $line');
			}
			input.on("data", (data: js.node.Buffer) -> {
				var parts = (pending + data.toString()).split("\n");
				pending = parts.pop();
				for (line in parts)
					addLine(line);
			});
			input.on("end", () -> if (pending != "") addLine(pending));
		}

		process = js.node.ChildProcess.spawn(cmd, args, {cwd: cwd});
		readPipe(process.stdout);
		readPipe(process.stderr);

		var error = null;
		process.on("error", (e: js.lib.Error) -> error = e.message);
		process.on("close", (code: Int) -> {
			process = null;
			if (error != null) {
				hide.Ide.inst.quickError('Could not run "$cmd" ($error)', 10);
				state = Idle;
			} else {
				onExit(code, lines);
			}
		});
	}

	static function excerpt(lines: Array<String>, count: Int, first: Bool) {
		var lines = lines.filter((l) -> l != "");
		return (first ? lines.slice(0, count) : lines.slice(-count)).join("\n");
	}
}
