module settings;

import std.file: readText;
import arsd.dom: Document, Element;
import std.conv: to;
import std.typecons: Tuple;

class Settings {
	
	private string filename_;
	private Document doc_;
	private Element sets_; 
	
	public this(string filename) {
		filename_ = filename;
	
		doc_ = new Document(readText(filename), true, true);

		sets_ = doc_.requireSelector("settings");
	}
	
	@property 
	public auto get(T, alias settings_name)() {
        return (sets_.getElementsByTagName(settings_name)[0].innerText()).to!T;
    }
}
