package hide.view;

class CdbTable extends hide.ui.View<{}> {

	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : String;
	var tabCache : String;
	var view : hide.comp.cdb.ConfigView;

	public function new( ?state ) {
		super(state);
		editor = new hide.comp.cdb.Editor(config,{
			copy : () -> (ide.database.save() : Any),
			load : (v:Any) -> ide.database.load((v:String)),
			save : function() {
				ide.saveDatabase();
				haxe.Timer.delay(syncTabs,0);
			}
		});
		undo = editor.undo;
		currentSheet = this.config.get("cdb.currentSheet");
		view = cast this.config.get("cdb.view");
	}

	function syncTabs() {
		if( getTabCache() != tabCache || editor.getCurrentSheet() != currentSheet ) {
			currentSheet = editor.getCurrentSheet();
			rebuild();
		}
	}

	function getSheets() {
		return [for( s in ide.database.sheets ) if( !s.props.hide && (view == null || view.exists(s.name)) ) s];
	}

	function getTabCache() {
		return [for( s in getSheets() ) s.name].join("|");
	}

	override function onActivate() {
		if( editor != null ) editor.focus();
	}

	function setEditor(index:Int) {
		var sheets = getSheets();
		editor.show(sheets[index],tabContents[index]);
		haxe.Timer.delay(function() {
			// delay
			editor.focus();
			editor.onFocus = activate;
		},0);
		currentSheet = editor.getCurrentSheet();
		ide.currentConfig.set("cdb.currentSheet", sheets[index].name);
	}

	override function onDisplay() {
		var sheets = getSheets();
		if( sheets.length == 0 ) {
			element.html("No CDB sheet created, <a href='#'>create one</a>");
			element.find("a").click(function(_) {
				var sheet = ide.createDBSheet();
				if( sheet == null ) return;
				rebuild();
			});
			return;
		}
		element.addClass("cdb-view");
		var tabs = new hide.comp.Tabs(element, true);
		tabCache = getTabCache();
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			var sc = new hide.comp.Scrollable(tab);
			tabContents.push(sc.element);
		}
		if( tabs != null ) {
			tabs.onTabChange = setEditor;
			tabs.onTabRightClick = function(index) {
				editor.popupSheet(getSheets()[index], function() {
					var newSheets = getSheets();
					var delta = newSheets.length - sheets.length;
					var sshow = null;
					if( delta > 0 )
						sshow = newSheets[index+1];
					else if( delta < 0 )
						sshow = newSheets[index-1];
					else
						sshow = newSheets[index]; // rename
					if( sshow != null )
						currentSheet = sshow.name;
					if( getTabCache() != tabCache )
						rebuild();
				});
			};
		}

		if( sheets.length > 0 ) {
			var idx = 0;
			for( i in 0...sheets.length )
				if( sheets[i].name == currentSheet ) {
					idx = i;
					break;
				}
			tabs.currentTab = tabContents[idx].parent();
		}

		watch(@:privateAccess ide.databaseFile, () -> rebuild());
	}

	override function getTitle() {
		return "CDB"+ @:privateAccess (ide.databaseDiff != null ? " - "+ide.databaseDiff : "");
	}

	static var _ = hide.ui.View.register(CdbTable);

}
