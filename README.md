# Hide

Hide (Heaps IDE) is an extensible editor that can be used as a middleware for various tasks, such as:
- preview 3D models and textures
- edit materials properties
- create timeline based visual effects and movements
- create whole 3D levels, place lights, paint terrain, bake shadow maps and volumetric light maps
- create and edit 2D and 3D particles systems
- edit and modify your [Castle](https://github.com/ncannasse/castle) Database
- extend by adding game specific prefabs
- extend with your own game specific editors


## Configuration

In your project's resource folder, you can create a `props.json` configuration file to override Hide's default settings. Refer to `bin/defaultProps.json` for the list of available settings. 


## Extending Hide

### Custom plugin

In your project, create an hxml configuration for building the plugin. Example:

    # hide-plugin.hxml
    -cp src
    -lib hide
    --macro hide.Plugin.init()
    -js hide-plugin.js
    -debug
    HideImports

`HideImports.hx` here is just a file that lists all the classes you want to embed in your plugin. Example:

    // HideImports.hx
    import prefabs.MyPrefab1;
    import prefabs.MyPrefab2;

Running `haxe hide-plugin.hxml` should now generate a `hide-plugin.js` plugin file.

In your project configuration file (`res/props.json`) you can now include this file like so:

    {
        "plugins": ["../hide-plugin.js"]
    }


### Custom prefab

Example of a project-specific custom prefab:

    import hrt.prefab.Context;
    import hrt.prefab.Library;

    class MyPrefab extends hrt.prefab.Object3D {
        
        public function new(?parent) {
            super(parent);
            type = "myprefab";
        }

        override function make(ctx:Context):Context {
            var ret = super.make(ctx);
            // Custom code...
            return ret;
        }

        #if editor

        override function getHideProps() : hide.prefab.HideProps {
            return { icon : "cog", name : "MyPrefab" };
        }

        #end

        static var _ = Library.register("myprefab", MyPrefab);
    }
