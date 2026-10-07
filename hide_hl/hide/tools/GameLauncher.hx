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

class GameLauncherProcess {
	public var lines(default, null) : Array<String> = [];
	public var exitCode(default, null) : Null<Int> = null;

	var process : sys.io.Process;
	var messages = new sys.thread.Deque<String>();
	var pipes = new haxe.atomic.AtomicInt(2);
	var onLine : (text: String) -> Void;

	public function new(cmd: String, args: Array<String>, cwd: String, onLine: (text: String) -> Void) {
		this.onLine = onLine;

		var prevCwd = Sys.getCwd();
		Sys.setCwd(cwd);
		try {
			process = new sys.io.Process(cmd, args);
		} catch (e) {
			Sys.setCwd(prevCwd);
			throw e;
		}
		Sys.setCwd(prevCwd);

		readPipe(process.stdout);
		readPipe(process.stderr);
	}

	function readPipe(input: haxe.io.Input) {
		sys.thread.Thread.create(() -> {
			try {
				while (true)
					messages.add(input.readLine());
			} catch (e) {}
			pipes.sub(1);
		});
	}

	public function update() : Bool {
		var line = messages.pop(false);
		while (line != null) {
			line = StringTools.rtrim(line);
			lines.push(line);
			onLine(line);
			line = messages.pop(false);
		}

		if (pipes.load() != 0)
			return false;

		exitCode = process.exitCode(true);
		process.close();
		return true;
	}

	public function kill() {
		process.kill();
	}
}

class GameLauncher {
	static final GAME_LAUNCHER_HXML = "gameLauncher.hxml";

	public static var state(default, null) : State = Idle;

	static var process : GameLauncherProcess;
	static var target : GameTarget;
	static var stopRequested = false;

	public static function toggle() {
		if (state == Idle)
			play();
		else
			stop();
	}

	static function play() {
		if (!hide.Ide.inst.isProjectValid()) {
			hide.Ide.showError("No project opened");
			return;
		}

		var target = try findTarget() catch (e) {
			hide.Ide.showError(e.message);
			return;
		}

		if (target == null) {
			hide.Ide.showError('No .hxml with both a -main and a -hl output found in ${hide.Ide.inst.projectDir}');
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
		var hxml : String = hide.Ide.inst.config.user.get(GAME_LAUNCHER_HXML);
		if (hxml == null)
			return listTargets()[0]?.hxml;
		return haxe.io.Path.normalize(haxe.io.Path.isAbsolute(hxml) ? hxml : hide.Ide.inst.projectDir + "/" + hxml);
	}

	public static function setCurrentHxml(hxml: String) {
		var dir = hide.Ide.inst.projectDir + "/";
		hxml = hxml.split("\\").join("/");
		if (StringTools.startsWith(hxml.toLowerCase(), dir.toLowerCase()))
			hxml = hxml.substr(dir.length);
		hide.Ide.inst.config.user.set(GAME_LAUNCHER_HXML, hxml);
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

		hide.Ide.showInfo('Compiling ${target.main} ($hxml)');
		if (start("haxe", [hxml], haxe.io.Path.directory(target.hxml), "haxe"))
			state = Compiling;
	}

	static function run() {
		state = start("hl", [target.output], target.cwd, "game") ? Running : Idle;
	}

	static function start(cmd: String, args: Array<String>, cwd: String, logPrefix: String) : Bool {
		try {
			process = new GameLauncherProcess(cmd, args, cwd, (text) -> Sys.println('[$logPrefix] $text'));
		} catch (e) {
			hide.Ide.showError('Could not run "$cmd" (${e.message})');
			return false;
		}
		hide.Ide.inst.addUpdate(update);
		return true;
	}

	static function update(dt: Float) {
		if (!process.update())
			return;

		hide.Ide.inst.removeUpdate(update);
		var finished = process;
		process = null;

		switch (state) {
			case Compiling if (stopRequested):
				hide.Ide.showInfo("Compilation cancelled");
				state = Idle;
			case Compiling:
				if (finished.exitCode != 0) {
					hide.Ide.showError('Compilation failed :\n${excerpt(finished.lines, 8, true)}');
					state = Idle;
				} else {
					run();
				}
			case Running:
				if (finished.exitCode != 0 && !stopRequested)
					hide.Ide.showWarning('Game exited with code ${finished.exitCode}\n${excerpt(finished.lines, 8, false)}');
				state = Idle;
			case Idle:
		}
	}

	static function excerpt(lines: Array<String>, count: Int, first: Bool) {
		var lines = lines.filter((l) -> l != "");
		return (first ? lines.slice(0, count) : lines.slice(-count)).join("\n");
	}
}
