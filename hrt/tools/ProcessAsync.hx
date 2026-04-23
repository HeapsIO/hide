package hrt.tools;

/**
	Run a process asynchronously, calling the given callback once the execution
	of the process has been completed
**/
class ProcessAsync {
	var process : sys.io.Process;
	var onCompletion: (process: sys.io.Process) -> Void;
	var timer : haxe.Timer;

	public function new(command: String, ?args: Array<String>, onCompletion: (process: sys.io.Process) -> Void) {
		process = new sys.io.Process(command, args);
		this.onCompletion = onCompletion;
		timer = haxe.Timer.delay(update, 0);
	}

	function update() {
		if (process.exitCode() == null) {
			timer = haxe.Timer.delay(update, 0);
		} else {
			onCompletion(process);
			process.close();
			process = null;
		}
	}
}