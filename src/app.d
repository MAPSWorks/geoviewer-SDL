import std.stdio: writeln;
import std.path: baseName;
import std.conv: to;

import geoviewer: Geoviewer;
import settings: Settings;

int main(string[] args)
{ 
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

	// create viewer
	auto geoviewer = new Geoviewer(width, height, lon, lat, url, cache_path);

	// run it
	geoviewer.run();

	geoviewer.close();

	return 0;
}
