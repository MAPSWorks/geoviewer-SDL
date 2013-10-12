module settings;

import std.file: readText;
import std.conv: to;
import std.json: JSONValue, parseJSON;

class Settings {
private:
	string filename_;
	JSONValue json_;

public:

	this(string filename) {
		filename_ = filename;

		json_ = parseJSON(readText(filename_));
	}

	@property get(T, alias string settings_name)() {
		return (json_[settings_name].str).to!T;
    }
}
