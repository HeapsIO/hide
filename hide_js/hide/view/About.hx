package hide.view;

class About extends hide.ui.View<{}> {

	public function new(state) {
		super(state);
	}

	override function getTitle() {
		return "About";
	}

	override function onDisplay() {
		element.get(0).innerHTML = "";
		var icons = @:privateAccess ide.statusIcons;
		hide.html.Html.build(element.get(0),
			<div class="about hide-scroll">
				<div class="header">
					<img src={"res/" + (ide.isCDB ? "cdb" : "hide") + ".png"}/>
					<span>${ide.isCDB ? "CastleDB" : "Hide"}</span>
				</div>
				for( section in getSections() ) {
					<h2>${section.title}</h2>
					<div class="entries">
						for( e in section.entries ) {
							<span class="name">${e.name}</span>
							<span>${e.value}</span>
						}
					</div>
				}
				<div if(icons != null)>
					<h2>Status</h2>
					${icons}
				</div>
			</div>
		);
	}

	function getSections() : Array<{ title : String, entries : Array<{ name : String, value : String }> }> {
		var versions = js.Node.process.versions;

		var commit = hide.Ide.getGitCommitHashAndDate();
		if( commit == "dev" )
			commit = 'dev (${js.node.Path.basename(js.node.Path.dirname(js.Node.__dirname))})';
		var build = [
			{ name : "Driver", value : #if dx12 "DirectX 12" #else "WebGL" #end },
			{ name : "Commit", value : commit == "" ? "unknown" : commit },
			{ name : "Build date", value : sys.FileSystem.stat(js.Node.__dirname + "/hide.js").mtime.toString() },
			{ name : "Path", value : ide.appPath },
		];

		var runtime = [
			{ name : "Electron", value : versions.get("electron") },
			{ name : "Chromium", value : versions.get("chrome") },
			{ name : "Node", value : versions.get("node") },
			{ name : "OS", value : Sys.systemName() + " " + js.node.Os.release() },
		];
		#if !dx12
		runtime.push({ name : "GPU", value : getWebGLRenderer() });
		#end

		var project = [
			{ name : "Project", value : ide.projectDir },
			{ name : "Resources", value : ide.resourceDir },
			{ name : "Renderer", value : h3d.mat.MaterialSetup.current.name },
			{ name : "User data", value : ide.userDataPath },
		];

		return [
			{ title : "Build", entries : build },
			{ title : "Runtime", entries : runtime },
			{ title : "Project", entries : project },
			{ title : "Remote console", entries : [{ name : "Server", value : RemoteConsoleView.getStatusText() }] },
		];
	}

	#if !dx12
	static function getWebGLRenderer() : String {
		var gl = js.Browser.document.createCanvasElement().getContextWebGL2();
		var ext = gl.getExtension("WEBGL_debug_renderer_info");
		var name : String = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL);
		(gl.getExtension("WEBGL_lose_context") : Dynamic).loseContext();
		return name;
	}
	#end

	public static function refreshAll() {
		for( v in hide.Ide.inst.getViews(About) )
			v.rebuild();
	}

	static var _ = hide.ui.View.register(About, { position : Center });

}
