module backend;

import std.concurrency: spawn, send, Tid, thisTid, receiveTimeout, receiveOnly, spawnLinked, OwnerTerminated, LinkTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln;
import std.exception: enforce;
import std.conv: text;

import derelict.freeimage.freeimage: DerelictFI;

import tile;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:

	enum childFailed = "child failed";
	enum tileLoadingFailed = "tile loading failed";

	string url_, cache_path_;

	static void downloading(Tid parent, Tid frontend)
	{
		DerelictFI.load();
		while(true)
        {
            uint zoom, x, y;
            string path, url;

            try
            {
            	// wait for tile descripton to process
                //                      zoom  x     y     path    url
                auto msg = receiveOnly!(uint, uint, uint, string, string)();
                
                zoom = msg[0];
                x = msg[1];
                y = msg[2];
                path = msg[3];
                url = msg[4];
            }
            catch(OwnerTerminated ot)
            {
            	// normal exit
            	break;
            }
            catch(Throwable t) 
            {
                debug writeln("receiveOnly failed: ", t.msg);
                parent.send(thisTid, childFailed, zoom, x, y); // this means that command from parent wasn't received, child thread crashes
                							 			       // and parent should relaunch thread. Zoom, x and y are dummy and has no sense
                							 			       // because they may have invalid value.
                break;
            }

            try 
            {
                version(none)
                {
                	import std.random;
	                auto i = uniform(0, 15);
	                if(i == 10)
	                	throw new Error("error imitation");
	            }

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
					
					tex_coords = [ 0.00, 1.00,  1.00, 1.00,  0.00, 0.00,  1.00, 0.00 ];
				}
				frontend.send(cast(shared) tile);
            }
            catch(OwnerTerminated ot) 
            {
                // normal exit
                break;
            }
            catch(Exception e) 
            {
                debug writeln("exception: ", e.msg);
            }
            catch(Throwable t) 
            {
                debug writeln("throwable: ", t.msg);
                parent.send(thisTid, tileLoadingFailed, zoom, x, y);// this means that tile loading failed, child thread crashes
                							 			 	   // and parent should relaunch thread with the specific zoom, 
                							 			 	   // x and y values to try loading once again.
                break;
            }
        }
		DerelictFI.unload();
	}

	static run(string url, string cache_path)
	{
		enum maxWorkers = 32;
	    Tid[maxWorkers] workers;
	    uint current_worker;

		auto frontend = receiveOnly!Tid();
		enforce(frontend != Tid.init, "Wrong frontend tid.");
		enforce(frontend != thisTid, "frontend and backend shall be running in different threads!");
		try 
		{
			// prepare workers
	        foreach(i; 0..maxWorkers)
	            workers[i] = spawnLinked(&downloading, thisTid, frontend); // anwers will be send to frontend immediatly
			
			uint zoom = 3;
			if(zoom > 18)
				zoom = 18;
			if(zoom < 0)
				zoom = 0;
			uint n = pow(2, zoom);
			
			frontend.send("startTileSet", n * n); // start new tile set

			foreach(uint y; 0..n)
				foreach(uint x; 0..n)
				{
					auto current_tid = workers[current_worker];
                    try
					{
						current_tid.send(zoom, x, y, cache_path, url);
	                    current_worker++;
	                    if(current_worker == maxWorkers)
	                        current_worker = 0;
					}
					catch(LinkTerminated lt)
					{
						// just ignore it
						debug writeln("Child terminated");
					}
				}

			// talk to child threads
	        bool msg; 
	        bool running = true;
	        do{     
	            msg = receiveTimeout(dur!"msecs"(10),
	            	(Tid tid, string text, uint zoom, uint x, uint y)
	            	{
	            		debug writeln(text);
	            		if(text == childFailed)
	            		{
	            			foreach(uint i, w; workers)
	            				if(w == tid)
	            				{
	            					workers[i] = spawnLinked(&downloading, thisTid, frontend);
	            					debug writeln(childFailed, " received");
	            					running = false;
	            				}
	            		}
	            		else if(text == tileLoadingFailed)
	            		{
							foreach(uint i, w; workers)
	            				if(w == tid)
	            				{	
	            					workers[i] = spawnLinked(&downloading, thisTid, frontend);
	            					workers[i].send(zoom, x, y, cache_path, url);
	            					debug writeln(tileLoadingFailed, " received");
	            					running = false;
	            				}
	            		}
	            		else
	            		{
	            			debug stderr.writefln("Unknown type message is received from child:\ntext: %s, zoom: %d, x: %d, y: %d", text, zoom, x, y);
	            		}
	            	},
	            	(LinkTerminated lt)
	            	{
	            		debug writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Link terminated");
	            	},
	            	(OwnerTerminated ot)
	                {
	                    debug writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Owner terminated");
	                    running = false;
	                },
	                (Variant any)
	                {
	                    stderr.writeln("Unknown message received by BackEnd running thread: " ~ any.type.text);
	                }   
	            );
	        } while(running);
		}
		catch(Exception e)
		{
			stderr.writeln("some error occured:");
			stderr.writeln(e.msg);
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
