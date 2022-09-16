package hrt.impl;

@:enum
abstract TextureType(String) from String to String {
    var gradient;
    var path;       // Not used as a type inside the json (the playload is a string), default value
}