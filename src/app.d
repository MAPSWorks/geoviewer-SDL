import std.stdio: stderr, writeln, writefln;
import std.path: baseName;
import std.conv: to;

import frontend: FrontEnd;
import settings: Settings;
import gitinfo: gitCommit, gitDatetime;

int main(string[] args)
{

	writefln("commit hash: %s", gitCommit);
	writefln("commit datetime: %s", gitDatetime);

	if(args.length < 2)
	{
		writeln(
			"usage:\n" ~
			"	" ~ args[0].baseName ~ " settings_file_name\n"
		);
		return -1;
	}

	// load config
	string filename = args[1];
	Settings settings;
	{
		scope(failure)
		{
			writeln("Error reading file " ~ filename ~ ". Aborting...");
			return -1;
		}
		settings = new Settings(filename);
	}

	// read config

	// initial coordinates of camera
	double lon = settings.get!(double, "initlon");
	assert(lon >= -180 && lon <= 180, "longitude must be in range [-180, 180]");
	double lat = settings.get!(double, "initlat");
	assert(lat >= -90 && lat <= 90, "latitude must be in range [-90, 90]");
	// url to download tiles
	string url = settings.get!(string, "tile_url");
	// path to tile cache
	string cache_path = settings.get!(string, "cache_path");
	uint width = settings.get!(uint, "width");
	uint height = settings.get!(uint, "height");

	auto frontend = new FrontEnd(width, height, lon, lat, url, cache_path);
	scope(exit) frontend.close();

	try
	{
		frontend.run();
	}
	catch(Exception e)
	{
		stderr.writefln("Exception catched: %s\n", e.msg);
	}

	return 0;
}
