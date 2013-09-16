module backend;

import std.concurrency: spawn, send, Tid, thisTid, receiveTimeout, receiveOnly, OwnerTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln;
import std.exception: enforce;
import std.conv: text;
import std.file: exists, mkdirRecurse, dirName;
import std.path: buildNormalizedPath, absolutePath;
import std.net.curl: download;

import derelict.sdl2.image;

import tile;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:
	string url_, cache_path_;

	static string downloadTile(uint zoom, uint tilex, uint tiley)
	{
		string url = "http://a.tile.openstreetmap.org/";
		auto local_path = "cache/OSM-standard";
		
		string absolute_path = absolutePath(local_path);
	    auto filename = tiley.text ~ ".png";
	    auto full_path = buildNormalizedPath(absolute_path, zoom.text, tilex.text, filename);

	    if(!exists(full_path) && url) {
	        //trying to download from openstreet map
	        auto dir = dirName(full_path);
	        if(!exists(dir))
	            mkdirRecurse(dir);
	        download(url ~ zoom.text ~ "/" ~ tilex.text ~ "/" ~ filename, full_path);
	    }

	    return full_path;		
	}

	static run()
	{
		DerelictSDL2Image.load();

		auto frontend = receiveOnly!Tid();
		enforce(frontend != Tid.init, "Wrong frontend tid.");
		enforce(frontend != thisTid, "frontend and backend shall be running in different threads!");
		try 
		{
			frontend.send("startTileSet", 4u); // start new tile set of 3 tiles

			foreach(i; 0..4u)
			{
				try // ignore the failure while loading single tile
				{
					string tile_path = downloadTile(7, i+111, 44);
					auto tile = Tile.loadFromFile(tile_path);
					with(tile)
					{
						vertices = [ -1.0 + 0.5*i, -0.0,  -0.5 + 0.5*i, -0.0,  -1.0 + 0.5*i, 0.5,  -0.5 + 0.5*i, 0.5 ];
						tex_coords = [ 0.00, 0.00,  1.00, 0.00,  0.00, 1.00,  1.00, 1.00 ];
					}
					frontend.send(cast(shared) tile);
				}
				catch(Throwable t)
				{
					stderr.writeln("some error occured:");
					stderr.writeln(t.msg);
				}
			}

		}
		catch(Throwable t)
		{
			stderr.writeln("some error occured:");
			stderr.writeln(t.msg);
		}

		DerelictSDL2Image.unload();
	}

public:

	this(double lon, double lat, string url, string cache_path)
	{
		url_ = url;
		cache_path_ = cache_path;
	}

	// run backend in other thread
	Tid runAsync()
	{
		return spawn(&run);
	}

	void close()
	{
		
	}

    void receiveMsg()
    {
		// talk to logic thread
        bool msg;   
        do{     
            msg = receiveTimeout(dur!"usecs"(1),
                (OwnerTerminated ot) {
                    writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Owner terminated");
                },
                (Variant any) {
                    stderr.writeln("Unknown message received by GUI thread: " ~ any.type.text);
                }   
            );
        } while(msg);
    }
}
