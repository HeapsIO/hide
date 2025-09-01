package hide.view;

import hide.tools.FileManager;
import hide.tools.FileManager.FileEntry;

typedef FavoriteEntry = {
	parent : FavoriteEntry,
	children : Array<FavoriteEntry>,
	?ref : FileEntry,
}

typedef FileBrowserState = {
	savedLayout: Layout,
}

enum abstract Layout(String) {
	var SingleTree;
	var SingleMiniature;
	var Vertical;
	var Horizontal;
}

class FileBrowser extends hide.ui.View<FileBrowserState> {
	static var FAVORITES_KEY = "filebrowser_favorites";

	var fileTree: Element;
	var fileIcons: Element;

	var root : FileEntry;
	var breadcrumbs : Element;

	var layout(default, set): Layout;

	function set_layout(newLayout: Layout) : Layout {
		layout = newLayout;
		state.savedLayout = layout;
		saveState();

		element.find("file-browser").toggleClass("vertical", layout == Vertical);
		element.find("file-browser").toggleClass("single", layout == SingleTree);

		element.find(".left").width(layout == Horizontal ? "300px" : "auto");  // reset splitter width
		element.find(".left").height(layout == Vertical ? "300px" : "");  // reset splitter height
		element.find(".left").toggle(layout != SingleMiniature);
		element.find(".right").toggle(layout != SingleTree);
		element.find(".splitter").toggle(layout != SingleTree && layout != SingleMiniature);
		resize.layoutDirection = layout == Horizontal ? Horizontal : Vertical;

		fullRefresh();

		return newLayout;
	}

	override function new(state) {
		super(state);
		saveDisplayKey = "fileBrowser";

		this.favorites = getDisplayState(FAVORITES_KEY);
		if (this.favorites == null)
			this.favorites = [];
	}

	override function buildTabMenu():Array<hide.comp.ContextMenu.MenuItem> {
		var menu = super.buildTabMenu();

		menu.push({isSeparator: true});
		menu.push({
			label: "Display",
			menu: [
				{
					label: "File Tree",
					radio: () -> layout == SingleTree,
					click: () -> layout = SingleTree,
					stayOpen: true,
				},
				{
					label: "Gallery",
					radio: () -> layout == SingleMiniature,
					click: () -> layout = SingleMiniature,
					stayOpen: true,
				},
						{
					label: "Horizontal",
					radio: () -> layout == Horizontal,
					click: () -> layout = Horizontal,
					stayOpen: true,
				},
				{
					label: "Vertical",
					radio: () -> layout == Vertical,
					click: () -> layout = Vertical,
					stayOpen: true,
				},
			]
		});

		menu.push({
			label: "Dock",
			menu: [{
				label: "Left",
				click: () -> {
					saveState();
					var newState : FileBrowserState = haxe.Json.parse(haxe.Json.stringify(state));
					newState.savedLayout = Vertical;
					close();
					ide.open("hide.view.FileBrowser", newState, hide.ui.View.DisplayPosition.Left);
				}
			},
			{
				label: "Bottom",
				click: () -> {
					saveState();
					var newState : FileBrowserState = haxe.Json.parse(haxe.Json.stringify(state));
					newState.savedLayout = Horizontal;
					close();
					ide.open("hide.view.FileBrowser", newState, hide.ui.View.DisplayPosition.Bottom);
				}
			},
			]
		});

		return menu;
	}


	var currentFolder : FileEntry;
	var currentSearch : Array<FileEntry> = [];
	var currentSearchRanges : Map<FileEntry, hide.comp.FancySearch.SearchRanges> = [];
	var searchString: String = "";
	var fancyGallery : hide.comp.FancyGallery<FileEntry>;
	var fancyTree: hide.comp.FancyTree<FileEntry>;
	var collapseSubfolders : Bool;
	var collapseSubfoldersButton : js.html.Element;

	var gallerySearchFullPath : Bool = false;
	var gallerySearchFullPathButton : js.html.Element;

	var filterButton : js.html.Element;
	var filterEnabled(default, set) : Bool;
	var filters : Map<String, {exts: Array<String>, icon: String}> = [];
	var filterState : Map<String, Bool> = [];
	var delaySelectGallery: String = null;
	var delaySelectFileTree: String = null;
	var delayedSelectItem : FileEntry = null;
	var stats: js.html.Element;
	var statFileCount: Int = 0;
	var statFileFiltered: Int = 0;

	var favorites : Array<String>;
	var favoritesTree : hide.comp.FancyTree<FavoriteEntry>;

	function set_filterEnabled(v : Bool) {
		var anySet = false;
		for (key => value in filterState) {
			if (value == true) {
				anySet = true;
				break;
			}
		}

		filterEnabled = anySet && v;

		filterButton.classList.toggle("selected", filterEnabled);
		saveDisplayState("filterEnabled", filterEnabled);
		queueGalleryRefresh();
		return v;
	}

	function saveFilterState() {
		saveDisplayState("filterState", [for(k in filterState.keys()) k]);
	}

	function syncCollapseSubfolders() {
		collapseSubfoldersButton.classList.toggle("selected", collapseSubfolders);
		saveDisplayState("collapseSubfolders", collapseSubfolders);
		queueGalleryRefresh();
	}

	function syncGallerySearchFullPath() {
		gallerySearchFullPathButton.classList.toggle("selected", gallerySearchFullPath);
		saveDisplayState("gallerySearchFullPath", gallerySearchFullPath);
		queueGalleryRefresh();
	}

	var galleryRefreshQueued = false;
	function queueGalleryRefresh() {
		if (!galleryRefreshQueued) {
			galleryRefreshQueued = true;
			js.Browser.window.requestAnimationFrame((_) -> onGalleryRefreshInternal());
		}
	}


	function onGalleryRefreshInternal() {
		galleryRefreshQueued = false;
		hide.tools.FileManager.inst.clearRenderQueue();
		currentSearch = [];
		currentSearchRanges = [];
		statFileCount = 0;
		statFileFiltered = 0;

		var validFolder = currentFolder;
		while(validFolder != null && !sys.FileSystem.exists(validFolder.getPath())) {
			validFolder = validFolder.parent;
		}
		if (validFolder == null) {
			validFolder = root;
		}
		if (validFolder != currentFolder) {
			currentFolder = validFolder;
			fancyTree.clearSelection();
			fancyTree.selectItem(currentFolder);
		}

		if (searchString.length == 0 && !collapseSubfolders && !filterEnabled) {
			currentSearch = currentFolder.children;
			currentSearch = currentSearch.filter(filterFiles);
			statFileFiltered = currentSearch.length;
		} else {
			var exts = [];
			if (filterEnabled) {
				for (name => active in filterState) {
					if (active) {
						for (ext in filters.get(name).exts) {
							exts.push(ext);
						}
					}
				}
			}

			var base = currentFolder.getRelPath();

			var query = hide.comp.FancySearch.createSearchQuery(searchString);

			function rec(files: Array<FileEntry>) {
				for (file in files) {
					if (file.kind == Dir && (collapseSubfolders || searchString.length > 0)) {
						if (file.children == null) {
							throw "null children";
						}
						rec(file.children);
					}
					else {
						if (!filterFiles(file))
							continue;

						statFileFiltered ++;
						if (filterEnabled && file.kind == File) {
							var ext = file.name.split(".").pop().toLowerCase();

							if (!exts.contains(ext)) {
								continue;
							}
						}

						if (searchString.length > 0) {
							var name = if (gallerySearchFullPath) {
								file.getRelPath().substr(base.length);
							} else {
								file.name;
							}

							var ranges = hide.comp.FancySearch.computeSearchRanges(name, query);
							if (ranges == null) {
								continue;
							}

							if (gallerySearchFullPath == true) {
								for (i in 0...ranges.length) {
									ranges[i] = hxd.Math.imax(ranges[i] - (name.length - file.name.length), 0);
								}
							}
							currentSearchRanges.set(file, ranges);
						}

						currentSearch.push(file);
					}
				}
			}

			rec(currentFolder.children);
		}

		currentSearch.sort(FileEntry.compareFile);

		statFileCount = currentSearch.length;
		statFileFiltered -= statFileCount;
		refreshStats();

		for (i => _ in currentSearch) {
			var child = currentSearch[currentSearch.length - i - 1];
			if ((child.iconPath == null || child.iconPath == "loading") && child.kind == File) {
				child.iconPath = "loading";
				hide.tools.FileManager.inst.renderMiniature(child.getPath(), (path: String) -> {child.iconPath = path; fancyGallery.queueRefresh();} );
			}
		}

		fancyGallery.queueRefresh(Items);

		if (delayedSelectItem != null) {
			fancyGallery.selectItem(delayedSelectItem);
			delayedSelectItem = null;
		}
	}

	function refreshStats() {
		stats.innerText = 'Showing ${hide.comp.SceneEditor.splitCentaines(statFileCount)} files (${hide.comp.SceneEditor.splitCentaines(statFileFiltered)} filtered)';
	}

	function onFileChange(file: FileEntry) {
		if (delaySelectFileTree != null) {
			var item = FileManager.inst.getFileEntry(delaySelectFileTree);
			if (item != null) {
				fancyTree.selectItem(item, false);
				delaySelectFileTree = null;
			}
		}

		if (delaySelectGallery != null) {
			var item = FileManager.inst.getFileEntry(delaySelectGallery);
			if (item != null) {
				fancyGallery.selectItem(item);
				delaySelectGallery = null;
			}
		}

		fancyTree.invalidateChildren(file);
		queueGalleryRefresh();
	}

	function fullRefresh() {
		fancyTree.rebuildTree();
		queueGalleryRefresh();
	}

	var resize : hide.comp.ResizablePanel;

	function filterFiles(entry: FileEntry) {
		return !entry.ignored;
	}

	public function refreshVCS() {
		fancyTree.queueRefresh(RegenHeader);
		fancyGallery.queueRefresh(RegenHeader);
	}

	function getIcon(item : FileEntry) : String {
		var vcsClass = switch(item.vcsStatus) {
			case None: "";
			case UpToDate: Ide.inst.ideConfig.svnShowVersionedFiles ? "fancy-status-icon fancy-status-icon-ok" : "";
			case Modified: Ide.inst.ideConfig.svnShowModifiedFiles ? "fancy-status-icon fancy-status-icon-modified" : "";
		};

		if (item.kind == Dir)
			return '<div class="ico ico-folder ${vcsClass}"></div>';
		var ext = Extension.getExtension(item.name);
		if (ext != null) {
			if (ext?.options.icon != null) {
				return '<div class="ico ico-${ext.options.icon} ${vcsClass}" title="${ext.options.name ?? "Unknown"}"></div>';
			}
		}
		return '<div class="ico ico-file ${vcsClass}" title="Unknown"></div>';
	}

	override function onDisplay() {
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());

		root = FileManager.inst.fileRoot;

		var browserLayout = new Element('
			<file-browser>
				<div class="left">
					<fancy-scroll>
						<div class="top"></div>
						<div class="bot"></div>
					</fancy-scroll>
				</div>
				<div class="right" tabindex="-1">
					<fancy-toolbar class="fancy-small shadow">
						<fancy-button class="btn-parent quiet" title="Go to parent folder">
							<fancy-image style="background-image:url(\'res/icons/svg/file_parent.svg\')"></fancy-image>
						</fancy-button>
						<fancy-breadcrumbs></fancy-breadcrumbs>
						<fancy-flex-fill></fancy-flex-fill>


						<fancy-button class="btn-collapse-folders">
							<span class="ico ico-folder-open-o" title="Display all files in subfolders"></span>
						</fancy-button>
						<fancy-separator></fancy-separator>

						<fancy-button class="btn-filter" title="Filter file by type">
							<span class="ico ico-filter"></span>
						</fancy-button>

						<fancy-button class="compact bnt-filter-dropdown" title="Choose filters">
							<span class="ico ico-chevron-down"></span>
						</fancy-button>

						<fancy-separator></fancy-separator>

						<fancy-search class="fb-search"></fancy-search>
						<fancy-button class="btn-seach-full-path" title="Search in files path in addition of the files name">
							<fancy-icon class="med" style="mask-image:url(\'res/icons/svg/search_folder.svg\')"></fancy-icon>
						</fancy-button>
					</fancy-toolbar>
					<fancy-gallery></fancy-gallery>
					<fancy-toolbar class="footer">
					<fancy-flex-fill></fancy-flex-fill>
					<span class="stats"></span>
					<fancy-toolbar>
				</div>
			</file-browser>
		').appendTo(element);

		stats = browserLayout.find(".stats").get(0);

		resize = new hide.comp.ResizablePanel(Horizontal, element.find(".left"), After);

		breadcrumbs = browserLayout.find("fancy-breadcrumbs");

		var search = new hide.comp.FancySearch(null, browserLayout.find(".fb-search"));
		search.onSearch = (string, _) -> {
			searchString = string.toLowerCase();
			queueGalleryRefresh();
		};

		var btnParent = browserLayout.find(".btn-parent");
		btnParent.get(0).onclick = (e: js.html.MouseEvent) -> {
			if (currentFolder.parent != null) {
				openDir(currentFolder.parent, true);
			}
		}

		// Favorites tree
		favoritesTree = new hide.comp.FancyTree<FavoriteEntry>(browserLayout.find(".left").find(".top"), { saveDisplayKey: "fileBrowserTree_Favorites" } );
		favoritesTree.getChildren = (file: FavoriteEntry) -> {
			function rec(parent : FavoriteEntry) {
				if (parent.ref.children == null)
					return;
				for (c in parent.ref.children) {
					var f = { parent : parent, children : [], ref: FileManager.inst.getFileEntry(c.path) };
					parent.children.push(f);
					rec(f);
				}
			}

			if (file == null) {
				var fav : FavoriteEntry = {
					parent : null,
					children : [],
					ref : null
				}

				fav.children = [];
				for (f in favorites) {
					// Ref could be null if this f is a favorite of another project
					var ref = FileManager.inst.getFileEntry(f);
					if (ref == null)
						continue;
					var c = { parent: fav, children: [], ref: ref }
					fav.children.push(c);
					rec(c);
				}

				return [fav];
			}

			if (file?.ref?.kind == File)
				return null;
			if (file.children == null)
				throw "null children";

			return file.children;

			// return [for (c in file.children) { parent: file, children: [], ref: FileManager.inst.getFileEntry(c.ref.path) }];
		};
		favoritesTree.getName = (file: FavoriteEntry) -> return file.ref == null ? "Favorites" : file?.ref.name;
		favoritesTree.getUniqueName = (file: FavoriteEntry) -> {
			if (file == null)
				return "";
			if (file.ref == null)
				return "favorites";
			var relPath = file.ref.name;
			var p = file.parent;
			while (p != null) {
				var name = p.ref == null ? "favorites" : p.ref.name;
				relPath = name + "/" + relPath;
				p = p.parent;
			}
			return relPath;
		}
		favoritesTree.getIcon = (file: FavoriteEntry) -> {
			if (file.parent == null)
				return '<div class="ico ico-star"></div>';

			var fav = file.parent.ref == null ? "fancy-status-icon fancy-status-icon-star" : "";
			if (file.ref.kind == Dir)
				return '<div class="ico ico-folder $fav"></div>';
			var ext = Extension.getExtension(file.ref.name);
			if (ext != null) {
				if (ext?.options.icon != null) {
					return '<div class="ico ico-${ext.options.icon} $fav" title="${ext.options.name ?? "Unknown"}"></div>';
				}
			}
			return '<div class="ico ico-file $fav" title="Unknown"></div>';
		};
		favoritesTree.onContextMenu = (item: FavoriteEntry, event: js.html.MouseEvent) -> {
			event.stopPropagation();
			event.preventDefault();

			var options : Array<hide.comp.ContextMenu.MenuItem> = [];
			options.push({
				label: "Collapse",
				click: () -> {
					var collapseTarget = item;
					if (item.ref.kind != Dir)
						collapseTarget = item.parent;
					favoritesTree.collapseItem(collapseTarget);
				}
			});
			options.push({
				label: "Collapse All",
				click: () -> {
					for (child in @:privateAccess favoritesTree.rootData)
						favoritesTree.collapseItem(child.item);
				}
			});
			options.push({
				isSeparator: true
			});

			// Root favorite tree options
			var isFavoriteRoot = item?.parent == null;
			if (isFavoriteRoot) {
				options.push({
					label: "Clear Favorites",
					click: () -> {
						favorites = [];
						saveDisplayState(FAVORITES_KEY, favorites);
						favoritesTree.rebuildTree();
						this.favoritesTree.element.parent().hide();
					}
				});

				hide.comp.ContextMenu.createFromEvent(event, options);
				return;
			}
			else {
				if (!this.favorites.contains(item.ref.getPath())) {
				options.push({ label: "Mark as Favorite", click : function() {
					this.favorites.push(item.ref.getPath());
					saveDisplayState(FAVORITES_KEY, this.favorites);
					this.favoritesTree.rebuildTree();
					this.favoritesTree.element.parent().show();
				}});
				}
				else {
					options.push({ label: "Remove from Favorite", click : function() {
						this.favorites.remove(item.ref.getPath());
						saveDisplayState(FAVORITES_KEY, this.favorites);
						this.favoritesTree.rebuildTree();
						if (this.favorites.length == 0)
							this.favoritesTree.element.parent().hide();
					}});
				}
			}

			hide.comp.ContextMenu.createFromEvent(event, options);
		};
		favoritesTree.onDoubleClick = (item: FavoriteEntry) -> {
			if (item?.ref?.kind == File)
				ide.openFile(item.ref.getPath());
			else
				favoritesTree.openItem(item);
		}
		favoritesTree.onSelectionChanged = (enterKey) -> {
			fancyTree.clearSelection();

			var selection = favoritesTree.getSelectedItems();

			// Sinc folder view with other filebrowser in SingleMiniature mode
			if (selection.length > 0) {
				if (selection[0].ref == null) return;

				openDir(selection[0].ref, false);
				var views = ide.getViews(hide.view.FileBrowser);
				for (view in views) {
					if (view == this)
						continue;
					if (view.layout == SingleMiniature) {
						view.openDir(selection[0].ref, false);
					}
				}
			}

			if (enterKey) {
				if (selection[0].ref.kind == File) {
					ide.openFile(selection[0].ref.getPath());
				}
			}
		}

		favoritesTree.rebuildTree();

		if (this.favorites.length == 0)
			this.favoritesTree.element.parent().hide();
			
		// Ressources tree
		fancyTree = new hide.comp.FancyTree<FileEntry>(browserLayout.find(".left").find(".bot"), { saveDisplayKey: "fileBrowserTree_Main", search: true, customScroll: element.find("fancy-scroll").get(0) } );
		fancyTree.getChildren = (file: FileEntry) -> {
			if (file == null)
				return [root];
			if (file.kind == File)
				return null;
			if (file.disposed)
				throw "disposed file";
			if (file.children == null)
				throw "null children";

			if (layout == SingleTree) {
				return file.children.filter(filterFiles);
			}
			return file.children.filter((file) -> file.kind == Dir && filterFiles(file));
		};

		fancyTree.getName = (file: FileEntry) -> return file?.name;
		fancyTree.getUniqueName = (file: FileEntry) -> file?.getRelPath();

		fancyTree.getIcon = getIcon;

		fancyTree.onNameChange = renameHandler;

		fancyTree.onSearch = () -> {
			favoritesTree.element.parent().hide();
		}

		fancyTree.onSearchEnd = () -> {
			if (this.favorites.length > 0)
				favoritesTree.element.parent().show();
		}

		fancyTree.dragAndDropInterface =
		{
			onDragStart: function(file: FileEntry, e: hide.tools.DragAndDrop.DragData) : Bool {
				var selection = fancyTree.getSelectedItems();
				if (selection.length <= 0)
					return false;
				e.data.set("drag/filetree", selection);
				ide.setData("drag/filetree", cast selection);
				return true;
			},
			getItemDropFlags: function(target: FileEntry, e: hide.tools.DragAndDrop.DragData) : hide.comp.FancyTree.DropFlags {
				if (target == null)
					return Reorder;

				var fileEntries : Array<FileEntry> = cast e.data.get("drag/filetree") ?? [];
				fileEntries = fileEntries.copy();
				var containsFiles = fileEntries != null && fileEntries.length > 0;

				if (!containsFiles)
					return hide.comp.FancyTree.DropFlags.ofInt(0);

				// Can't drop a file on itself
				fileEntries.remove(target);

				if (fileEntries.length == 0)
					return hide.comp.FancyTree.DropFlags.ofInt(0);

				if (target.kind == Dir)
					return (Reorder:hide.comp.FancyTree.DropFlags) | Reparent;

				return Reorder;
			},
			onDrop: function(target: FileEntry, operation: hide.comp.FancyTree.DropOperation, e: hide.tools.DragAndDrop.DragData) : Bool {
				if (target.kind != Dir)
					target = target.parent;

				var fileEntries : Array<FileEntry> = cast e.data.get("drag/filetree") ?? [];
				fileEntries = fileEntries.copy();
				fileEntries.remove(target);

				var files = [ for (f in fileEntries) f.path ];
				if (files.length == 0)
					return false;

				if(!ide.confirm('Really move files :\n${files.join("\n")}\nto target folder :\n${target.getRelPath()}\n?\n(This could take a long time)')) {
					return true;
				}

				moveFiles(target.getRelPath(), files);

				return true;
			}
		}

		fancyTree.onContextMenu = contextMenu.bind(false);

		fancyTree.rebuildTree();
		fancyTree.openItem(root, true);

		fancyTree.onDoubleClick = (item: FileEntry) -> {
			if (item.kind == File)
				ide.openFile(item.getPath());
			else
				fancyTree.openItem(item);
		}

		var right = browserLayout.find(".right");
		right.get(0).onkeydown = (e: js.html.KeyboardEvent) -> {
			if (hide.ui.Keys.matchJsEvent("search", e, ide.currentConfig)) {
				e.stopPropagation();
				e.preventDefault();

				search.focus();
				return;
			}
		}

		fancyGallery = new hide.comp.FancyGallery<FileEntry>(null, browserLayout.find(".right fancy-gallery"));
		fancyGallery.getItems = () -> {
			return currentSearch;
		}

		fancyGallery.getName = (item : FileEntry) -> item.name;
		fancyGallery.getTitle = (item : FileEntry) -> item.getRelPath();
		fancyGallery.getItemRanges = (item: FileEntry) -> currentSearchRanges.get(item);

		fancyGallery.getThumbnail = (item : FileEntry) -> {
			if (item.kind == Dir) {
				return '<fancy-image style="background-image:url(\'res/icons/svg/big_folder.svg\')"></fancy-image>';
			}
			else if (item.iconPath == "loading") {
				return '<fancy-image class="loading" style="background-image:url(\'res/icons/loading.gif\')"></fancy-image>';
			}
			else if (item.iconPath != null) {
				var url = "file://" + item.iconPath;
				return '<fancy-image class="thumb" style="background-image:url(\'${url}\')"></fancy-image>';
			}
			else {
				return '<fancy-image style="background-image:url(\'res/icons/svg/file.svg\')"></fancy-image>';
			}
		};

		fancyGallery.getIcon = getIcon;

		fancyGallery.onDoubleClick = (item: FileEntry) -> {
			if (item.kind == File) {
				ide.openFile(item.getPath());
			} else {
				openDir(item, true);
			}
		}

		fancyGallery.visibilityChanged = (item: FileEntry, visible: Bool) -> {
			var path = item.getPath();
			hide.tools.FileManager.inst.setPriority(path, visible ? 1 : 0);
		}

		fancyGallery.dragAndDropInterface = {
			onDragStart: (item: FileEntry, dragData: hide.tools.DragAndDrop.DragData) -> {
				var selection = getItemAndSelection(item, true);
				dragData.data.set("drag/filetree", selection);
				ide.setData("drag/filetree", cast selection);
				return true;
			}
		}

		fancyGallery.onContextMenu = contextMenu.bind(true);

		if (Ide.inst.ideConfig.filebrowserDebugShowMenu) {
			browserLayout.find(".btn-collapse-folders").after(new Element('<fancy-button class="btn-debug"><span class="ico ico-bug"></span></fancy-button>'));
			var button = browserLayout.find(".btn-debug").get(0);
			button.onclick = (e) -> {
				hide.comp.ContextMenu.createDropdown(button, [
					{
						label: "Kill render thread",
						click: () -> {
							@:privateAccess hide.tools.FileManager.inst.cleanupGenerator();
						}
					}
				]);
			};
		}

		openDir(root, false);


		fancyTree.onSelectionChanged = (enterKey) -> {
			favoritesTree.clearSelection();

			var selection = fancyTree.getSelectedItems();

			// Sinc folder view with other filebrowser in SingleMiniature mode
			if (selection.length > 0) {
				openDir(selection[0], false);
				var views = ide.getViews(hide.view.FileBrowser);
				for (view in views) {
					if (view == this)
						continue;
					if (view.layout == SingleMiniature) {
						view.openDir(selection[0], false);
					}
				}
			}

			if (enterKey) {
				if (selection[0].kind == File) {
					ide.openFile(selection[0].getPath());
				}
			}
		}

		generateFilters();

		var savedFilters : Array<Dynamic> = getDisplayState("filterState") ?? [];
		for (filter in savedFilters) {
			if (filters.get(filter) != null) {
				filterState.set(filter, true);
			}
		}

		filterButton = browserLayout.find(".btn-filter").get(0);
		filterButton.onclick = (e: js.html.MouseEvent) -> {
			filterEnabled = !filterEnabled;
		}
		filterEnabled = getDisplayState("filterEnabled") ?? false;


		var filterMoreButton = browserLayout.find(".bnt-filter-dropdown").get(0);
		filterMoreButton.onclick = (e: js.html.MouseEvent) -> {
			var options : Array<hide.comp.ContextMenu.MenuItem> = [];

			for (name => info in filters) {
				options.push({
					label: name,
					checked: filterState.get(name) == true,
					click: () -> {
						if (filterState.get(name) == true) {
							filterState.remove(name);
						} else {
							filterState.set(name, true);
						}

						filterEnabled = true;
						saveFilterState();
						queueGalleryRefresh();
					},
					stayOpen: true,
				});
			}
			hide.comp.ContextMenu.createDropdown(filterMoreButton, options);
		}


		collapseSubfolders = getDisplayState("collapseSubfolders") ?? false;
		collapseSubfoldersButton = browserLayout.find(".btn-collapse-folders").get(0);
		collapseSubfoldersButton.onclick = (e: js.html.MouseEvent) -> {
			collapseSubfolders = !collapseSubfolders;
			syncCollapseSubfolders();
		}
		syncCollapseSubfolders();

		gallerySearchFullPath = getDisplayState("gallerySearchFullPath") ?? false;
		gallerySearchFullPathButton = browserLayout.find(".btn-seach-full-path").get(0);
		gallerySearchFullPathButton.onclick = (e: js.html.MouseEvent) -> {
			gallerySearchFullPath = !gallerySearchFullPath;
			syncGallerySearchFullPath();
		}
		syncGallerySearchFullPath();

		FileManager.inst.onFileChangeHandlers.push(onFileChange);
		FileManager.inst.onVCSStatusUpdateHandlers.push(refreshVCS);

		layout = state.savedLayout ?? Horizontal;
	}

	function renameHandler(item: FileEntry, newName: String) {
		if (newName.indexOf(".") == -1 && item.name.indexOf(".") >= 0) {
			newName += "." + item.name.split(".").pop();
		}

		var newPath = item.getRelPath().split("/");
		newPath.pop();
		newPath.push(newName);
		renameFile(item.getRelPath(), newPath.join("/"));
	}

	/**
		Path is relative to res folder
	**/
	function moveFiles(targetFolder: String, files: Array<String>) {
		var roots = getRoots(files);
		var outerFiles: Array<{from: String, to: String}> = [];
		for (root in roots) {
			var movePath = targetFolder + "/" + root.split("/").pop();
			outerFiles.push({from: ide.makeRelative(root), to: movePath});
		}

		var exec = execMoveFiles.bind(outerFiles);

		undo.change(Custom(exec));
		exec(false);
	}

	static function execMoveFiles(operations: Array<{from: String, to: String}>, isUndo: Bool) : Void {
		if (!isUndo) {
			for (file in operations) {
				// File could have been removed by the system in between our undo/redo operations
				if (sys.FileSystem.exists(hide.Ide.inst.getPath(file.from))) {
					try {
						FileManager.doRename(file.from, "/" + file.to);
					} catch (e) {
						hide.Ide.inst.quickError('move file ${file.from} -> ${file.to} failed : $e');
					}
				}
			}
		} else {
			for (file in operations) {
				// File could have been removed by the system in between our undo/redo operations
				if (sys.FileSystem.exists(hide.Ide.inst.getPath(file.to))) {
					try {
						FileManager.doRename(file.to, "/" + file.from);
					} catch (e) {
						hide.Ide.inst.quickError('move file ${file.from} -> ${file.to} failed : $e');
					}
				}
			}
		}
	}

	function renameFile(oldPath: String, newPath: String) {
		var exec = execMoveFiles.bind([{from: oldPath, to: newPath}]);
		undo.change(Custom(exec));
		exec(false);
	}

	override function destroy() {
		super.destroy();
		FileManager.inst.onFileChangeHandlers.remove(onFileChange);
	}

	function createNew( directoryFullPath : String, ext : Extension.ExtensionDesc, isGallery: Bool) {

		var file = ide.ask(ext.options.createNew + " name:");
		if( file == null ) return;
		if( file.indexOf(".") < 0 && ext.extensions != null )
			file += "." + ext.extensions[0].split(".").shift();

		var newFilePath = directoryFullPath + "/" + file;

		if( sys.FileSystem.exists(newFilePath) ) {
			ide.error("File '" + file+"' already exists");
			createNew(directoryFullPath, ext, isGallery);
			return;
		}

		// directory
		if( ext.component == null ) {
			sys.FileSystem.createDirectory(newFilePath);
			return;
		}

		var view : hide.view.FileView = Type.createEmptyInstance(Type.resolveClass(ext.component));
		view.ide = ide;
		view.state = { path : ide.getRelPath(newFilePath)};
		sys.io.File.saveBytes(newFilePath, view.getDefaultContent());

		ide.openFile(newFilePath);

		if (isGallery) {
			delaySelectGallery = newFilePath;
		} else {
			delaySelectFileTree = newFilePath;
		}
	}

	function getItemAndSelection(baseItem: FileEntry, isGallery: Bool) : Array<FileEntry> {
		var items = [];
		if (baseItem != null) {
			items.push(baseItem);
		}
		if (!isGallery) {
			for (item in fancyTree.getSelectedItems()) {
				hide.tools.Extensions.ArrayExtensions.pushUnique(items, item);
			}
		} else {
			for (item in fancyGallery.getSelectedItems()) {
				hide.tools.Extensions.ArrayExtensions.pushUnique(items, item);
			}
		}
		return items;
	}

	// Deduplicate paths if they are contained in a directory
	// also present in paths, to simplify bulk operations
	function getRoots(fullPaths: Array<String>) {
		var dirs : Array<String> = [];

		for (file in fullPaths) {
			if(sys.FileSystem.isDirectory(ide.getPath(file))) {
				dirs.push(file);
			}
		}

		// Find the minimum ammount of files that need to be moved
		var roots: Array<String> = [];
		for (file in fullPaths) {
			var isContainedInAnotherDir = false;
			for (dir2 in dirs) {
				if (file == dir2)
					continue;
				if (StringTools.contains(file, dir2)) {
					isContainedInAnotherDir = true;
					continue;
				}
			}
			if (!isContainedInAnotherDir) {
				roots.push(file);
			}
		}

		return roots;
	}

	public function reveal(path: String) {
		var item = FileManager.inst.getFileEntry(path);
		if (item == null)
			return;

		if (layout == SingleTree) {
			fancyTree.selectItem(item);
		} else {
			openDir(item.parent, true);
			delayedSelectItem = item;
			queueGalleryRefresh();
		}
	}

	function contextMenu(isGallery: Bool, item: FileEntry, event: js.html.MouseEvent) {
		event.stopPropagation();
		event.preventDefault();

		var options : Array<hide.comp.ContextMenu.MenuItem> = [];

		var collapseAll : hide.comp.ContextMenu.MenuItem = {
			label: "Collapse All",
			click: () -> {
				for (child in root.children) {
					fancyTree.collapseItem(child);
				}
			}
		};

		var implicitFolder = false;

		// if the user clicked on the background of the file tree, don't display anything
		if (item == null && !isGallery) {
			implicitFolder = true;
			item = root;
		}

		// if the user selected the "current" folder in the gallery
		// prevent move/delete ... operations on it to avoid confusion and wrong operations
		if (item == null) {
			implicitFolder = true;
			item = currentFolder;
		}

		var newMenu : Array<hide.comp.ContextMenu.MenuItem> = [];
		newMenu.push({
				label: "Directory",
				icon: "folder",
				click: createNew.bind(item.getPath(), { options : { createNew : "Directory" }, extensions : null, component : null }, isGallery),
			});

		var extIterator = Extension.EXTENSIONS.iterator();
		if (extIterator.hasNext())
			newMenu.push({isSeparator: true});
		for (e in extIterator) {
			if (e.options.createNew != null) {
				newMenu.push({
				label: e.options.createNew,
				click : function() : Void {
					createNew(item.getPath(), e, isGallery);
				},
				icon : e.options.icon,
				});
			}
		}

		if (item.kind == Dir) {
			options.push({
				label: "New ...",
				menu: newMenu,
			});
			options.push({
				isSeparator: true
			});
		}

		if (!isGallery) {

			options.push({
				label: "Collapse",
				click: () -> {
					var collapseTarget = item;
					if (item.kind != Dir)
						collapseTarget = item.parent;
					fancyTree.collapseItem(collapseTarget);
				}
			});

			options.push(collapseAll);
		}

		if (!implicitFolder) {
			if (options[options.length-1] != null && !options[options.length-1].isSeparator) {
				options.push({
					isSeparator: true,
					menu: newMenu,
				});
			}

			options.push({
				label: "Copy Path",
				click: () -> ide.setClipboard(item.getRelPath())
			});

			options.push({
				label: "Copy Absolute Path",
				click: () -> ide.setClipboard(item.getPath())
			});

			options.push({
				label : "Open in Explorer",
				click : () -> Ide.showFileInExplorer(item.getPath())
			});

			if (isGallery) {
				options.push({
					label : "Open in Resources", click : function() {
						ide.showFileInResources(item.getRelPath());
					}
				});
			}

			options.push({ label : "Find References", click : onFindPathRef.bind(item.getRelPath())});

			options.push({
				isSeparator: true,
				menu: newMenu,
			});

			options.push({
				label: "Clone", click: () -> {
					hide.tools.FileManager.inst.cloneFile(item);
				}
			});

			options.push({
				label: "Rename", click: () -> {
					if (!isGallery) {
						fancyTree.rename(item);
					} else {
						fancyGallery.rename(item, (newName:String) -> renameHandler(item, newName));
					}
				}, keys: config.get("key.rename"),
			});

			options.push({
				label: "Move", click: () -> {
					ide.chooseDirectory(function(dir) {
						var selection = getItemAndSelection(item, isGallery);
						var roots = FileManager.inst.getRoots(selection);
						moveFiles(dir, [for (file in roots) file.getRelPath()]);
					});
				}
			});


			options.push({
				label: "Delete", click: () -> {
					var selection = getItemAndSelection(item, isGallery);
					var roots = FileManager.inst.getRoots(selection);
					if(ide.confirm("Confirm deleting files : " + [for (r in roots) r.getRelPath()].join("\n") + '\n(Cannot be undone)'))
						FileManager.inst.deleteFiles(getItemAndSelection(item, isGallery));
				}
			});

			options.push({ label: "Replace Refs With", click : function() {
				ide.chooseFile(["*"], (newPath: String) -> {
					var selection = [for (file in getItemAndSelection(item, isGallery)) file.getRelPath()];
					if(ide.confirm('Replace all refs of $selection with $newPath ? This action can not be undone')) {
						for (oldPath in selection) {
							FileManager.replacePathInFiles(oldPath, newPath, false);
						}
						ide.message("Done");
					}
				});
			}});
		}

		if (!this.favorites.contains(item.getPath())) {
			options.push({ label: "Mark as Favorite", click : function() {
				this.favorites.push(item.getPath());
				saveDisplayState(FAVORITES_KEY, this.favorites);
				this.favoritesTree.rebuildTree();
				this.favoritesTree.element.parent().show();
			}});
		}
		else {
			options.push({ label: "Remove from Favorite", click : function() {
				this.favorites.remove(item.getPath());
				saveDisplayState(FAVORITES_KEY, this.favorites);
				this.favoritesTree.rebuildTree();
				if (this.favorites.length == 0)
					this.favoritesTree.element.parent().hide();
			}});
		}

		options.push({ label: "Refresh Thumbnail(s)", click : function() {
			var files = FileManager.inst.getRoots(getItemAndSelection(item, isGallery));
			for (file in files) {
				FileManager.inst.invalidateMiniature(file);
			}
			queueGalleryRefresh();
		}});

		if (ide.isSVNAvailable()) {
			options.push({ label : "", isSeparator: true });
			options.push({ label: "SVN Revert", click : function() {
				var fileList = FileManager.inst.createSVNFileList(getItemAndSelection(item, isGallery));
				js.node.ChildProcess.exec('cmd.exe /c start "" TortoiseProc.exe /command:revert /pathfile:"$fileList" /deletepathfile', { cwd: ide.getPath(ide.resourceDir) }, (error, stdout, stderr) -> {
					if (error != null)
						ide.quickError('Error while trying to revert files : ${error}');
				});
			}});
			options.push({ label: "SVN Log", click : function() {
				var path = item.getPath();
				js.node.ChildProcess.exec('cmd.exe /c start "" TortoiseProc.exe /command:log /path:"$path"', { cwd: ide.getPath(ide.resourceDir) }, (error, stdout, stderr) -> {
					if (error != null)
						ide.quickError('Error while trying to log file ${path} : ${error}');
				});
			}});
			options.push({ label: "SVN Blame", click : function() {
				var path = item.getPath();
				js.node.ChildProcess.exec('cmd.exe /c start "" TortoiseProc.exe /command:blame /path:"$path"', { cwd: ide.getPath(ide.resourceDir) }, (error, stdout, stderr) -> {
					if (error != null)
						ide.quickError('Error while trying to blame file ${path} : ${error}');
				});
			}});
		}

		hide.comp.ContextMenu.createFromEvent(event, options);
	}

	function onFindPathRef(path: String) {
		var refs = ide.search(path, ["hx", "prefab", "fx", "cdb", "json", "props", "ddt"], ["bin"]);
		ide.open("hide.view.RefViewer", null, null, function(view) {
			var refViewer : hide.view.RefViewer = cast view;
			refViewer.showRefs(refs, path, function() {
				ide.openFile(path);
			});
		});
	}

	function generateFilters() {
		for (ext => desc in Extension.EXTENSIONS) {
			var name = desc?.options.name;
			if (name == null)
				name = "unknown";
			var arr = hrt.tools.MapUtils.getOrPut(filters, name, {exts: [], icon: desc.options.icon});
			arr.exts.push(ext);
		}
	}

	function refreshBreadcrumbs() {
		breadcrumbs.empty();
		var path = [];
		var current = currentFolder;
		while (current != null) {
			path.push(current);
			current = current.parent;
		}

		for (i => _ in path) {
			var current = path[path.length-i-1];
			var button = new Element('<fancy-button class="quiet">${current.name}</fancy-button>');
			breadcrumbs.append(new Element(button));

			button.get(0).onclick = (e: js.html.MouseEvent) -> {
				openDir(current, true);
			}

			if (i < path.length - 1) {
				breadcrumbs.append(new Element('<fancy-breadcrumbs-separator>/</fancy-breadcrumbs-separator>'));
			}

		}
	}

	function openDir(item: FileEntry, syncTree: Bool) {
		if (item.kind == Dir) {
			currentFolder = item;
			queueGalleryRefresh();
		}

		if (syncTree) {
			fancyTree.selectItem(item, true);
		}

		refreshBreadcrumbs();
	}

	static var _ = hide.ui.View.register(FileBrowser, { width : 350, position : Bottom });
}