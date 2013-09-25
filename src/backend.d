module backend;

import std.concurrency: spawn, send, Tid, thisTid, receiveTimeout, receiveOnly, spawnLinked, OwnerTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln;
import std.exception: enforce;
import std.conv: text;

import tile;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:
	string url_, cache_path_;

	static void downloading(Tid parent)
	{
		while(true)
        {
            try {
            	// wait for tile descripton to process
                //                      zoom  x     y     path    url
                auto msg = receiveOnly!(uint, uint, uint, string, string)();
                
                auto zoom = msg[0];
                auto x = msg[1];
                auto y = msg[2];
                auto path = msg[3];
                auto url = msg[4];
                
                enum step = 256; // real size of tile in pixels
				double level_size = step * pow(2, zoom); // all tiles of the level with current zoom will take this amount of pixels

                string tile_path = Tile.downloadTile(zoom, x, y, url, path);
				auto tile = Tile.loadFromPng(tile_path);
				with(tile)
				{
					vertices.length = 8;
					vertices[0] = -level_size / 2 + x*step + 0; 
					vertices[1] = level_size / 4 /*probably should be just step?*/ - y*step + step; 

					vertices[2] = -level_size / 2 + x*step + step; 
					vertices[3] = level_size / 4 /*probably should be just step?*/ - y*step + step; 

					vertices[4] = -level_size / 2 + x*step + 0; 
					vertices[5] = level_size / 4 /*probably should be just step?*/ - y*step + 0; 

					vertices[6] = -level_size / 2 + x*step + step; 
					vertices[7] = level_size / 4 /*probably should be just step?*/ - y*step + 0; 
					
					tex_coords = [ 0.00, 0.00,  1.00, 0.00,  0.00, 1.00,  1.00, 1.00 ]; // we invert y coordinate, because opengl issue
				}
				parent.send(cast(shared) tile);
            }
            catch(OwnerTerminated ot) {
                break;
            }
            catch(Exception e) {
                writeln("exception: ", e.msg);
            }
            catch(Throwable t) {
                writeln("throwable: ", t.msg);
            }
        }
	}

	static run(string url, string cache_path)
	{
		enum maxWorkers = 1;
	    Tid[maxWorkers] workers;
	    uint current_worker;

		auto frontend = receiveOnly!Tid();
		enforce(frontend != Tid.init, "Wrong frontend tid.");
		enforce(frontend != thisTid, "frontend and backend shall be running in different threads!");
		try 
		{
			// prepare workers
	        foreach(i; 0..maxWorkers)
	            workers[i] = spawnLinked(&downloading, frontend); // anwers will be send to frontend immediatly

			
			uint zoom = 4;
			if(zoom > 18)
				zoom = 18;
			if(zoom < 0)
				zoom = 0;
			uint n = pow(2, zoom);
			
			frontend.send("startTileSet", n * n); // start new tile set

			foreach(uint y; 0..n)
				foreach(uint x; 0..n)
				{
					try // ignore the failure while loading single tile
					{
						auto current_tid = workers[current_worker];
                        current_tid.send(zoom, x, y, cache_path, url);
                        current_worker++;
                        if(current_worker == maxWorkers)
                            current_worker = 0;
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
		return spawn(&run, url_, cache_path_);
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
            	(OwnerTerminated ot)
                {
                    writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Owner terminated");
                },
                (Variant any)
                {
                    stderr.writeln("Unknown message received by GUI thread: " ~ any.type.text);
                }   
            );
        } while(msg);
    }
}
