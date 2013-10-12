module backend;

import std.concurrency: spawn, send, prioritySend, Tid, thisTid, receiveTimeout, receiveOnly, spawnLinked, OwnerTerminated, LinkTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln, writefln;
import std.exception: enforce;
import std.conv: text;
import std.math: pow;
import std.container: DList;
import std.typecons: Tuple;

import derelict.freeimage.freeimage: DerelictFI;

import tile: Tile, tile2world;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:

	enum childFailed = "child failed";
	enum tileLoadingFailed = "tile loading failed";

	string url_, cache_path_;

	static void downloading(Tid parent)
	{
		DerelictFI.load();
		scope(exit) DerelictFI.unload();
		auto running = true;
		size_t current_batch_id;

		while(running)
        {
        	int zoom, x, y;
            string path, url;

			// get tile batch id
			void handleTileBatchId(string text, size_t batch_id)
			{
				if(text == newTileBatch)
				{
					current_batch_id = batch_id;
				}
			}

			// get tile description to download
			void handleTileRequest(size_t batch_id, int x, int y, int zoom, string path, string url)
			{
				version(none)
                {
                	import std.random;
	                auto i = uniform(0, 15);
	                if(i == 10)
	                	throw new Error("error imitation");
	            }
	            if(batch_id < current_batch_id)  // ignore tile of previous requests
	            {
	            	return;
	            }

                enum step = 256; // real size of tile in pixels
				double level_size = step * pow(2, zoom); // all tiles of the level with current zoom will take this amount of pixels

                string tile_path;
                auto count = 0;
                // try to download five times
                do
                {
                	try
                	{
                		tile_path = Tile.download(zoom, x, y, url, path);
                		break;
                }
                	catch(Exception e)
                	{
                		debug writefln("%s. Retrying %d time...", e.msg, count);
                		count++;
                	}
                } while(count < 5);

                debug if(count >= 5) writeln("downloading failure");

				auto tile = Tile.loadFromPng(tile_path);
				with(tile)
				{
					vertices.length = 8;
					auto w = tile2world(x + 0, y + 0, zoom);
					vertices[0] = w.x;
					vertices[1] = w.y;

					w = tile2world(x + 1, y + 0, zoom);
					vertices[2] = w.x;
					vertices[3] = w.y;

					w = tile2world(x + 0, y + 1, zoom);
					vertices[4] = w.x;
					vertices[5] = w.y;

					w = tile2world(x + 1, y + 1, zoom);
					vertices[6] = w.x;
					vertices[7] = w.y;

					tex_coords = [ 0.00, 1.00,  1.00, 1.00,  0.00, 0.00,  1.00, 0.00 ];
				}
				parent.send(batch_id, cast(shared) tile, x, y, zoom);
			}

            try
            {
        	   	auto msg = receiveTimeout(dur!"msecs"(1),
					&handleTileBatchId,
					&handleTileRequest,
					(OwnerTerminated ot)
			        {
			        	// normal exit
			        	running = false;
			        }
				);
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
                running = false;
            }
        }
	}

	static run(string url, string cache_path)
	{
		enum maxWorkers = 32;
	    Tid[maxWorkers] workers;
	    uint current_worker;
	    size_t current_batch_id;
	    shared(Tile)[int][int][int] tile_cache;  // x, y, zoom

	    alias Tuple!(int, "x", int, "y", int, "zoom") TileDescription;
		DList!TileDescription tile_cache_content; // list of tile that cache contains
		size_t tile_cache_size; // current size of tile cache
		enum maxTileCacheSize = 256;

		auto frontend = receiveOnly!Tid();
		enforce(frontend != Tid.init, "Wrong frontend tid.");
		enforce(frontend != thisTid, "frontend and backend shall be running in different threads!");
		try
		{
			// prepare workers
	        foreach(i; 0..maxWorkers)
	            workers[i] = spawnLinked(&downloading, thisTid); // anwers will be send to frontend immediatly

			// talk to child threads
	        bool msg;
	        bool running = true;
	        do{
	            msg = receiveTimeout(dur!"msecs"(10),
	            	// error message from childs
	            	(Tid tid, string text, int zoom, int x, int y)
	            	{
	            		debug writeln(text);
	            		if(text == childFailed)
	            		{
	            			foreach(uint i, w; workers)
	            				if(w == tid)
	            				{
	            					workers[i] = spawnLinked(&downloading, thisTid);
	            					debug writeln(childFailed, " received");
	            					running = false;
	            				}
	            		}
	            		else if(text == tileLoadingFailed)
	            		{
							foreach(uint i, w; workers)
	            				if(w == tid)
	            				{
	            					workers[i] = spawnLinked(&downloading, thisTid);
	            					workers[i].send(zoom, x, y, cache_path, url);
	            					debug writeln(tileLoadingFailed, " received");
	            				}
	            		}
	            		else
	            		{
	            			debug stderr.writefln("Unknown type message is received from child:\ntext: %s, zoom: %d, x: %d, y: %d", text, zoom, x, y);
						}
					},
					// get new tile batch id
					(string text, size_t batch_id)
					{
						if(text == newTileBatch)
						{
							current_batch_id = batch_id;
							foreach(w; workers)
            				{
            					w.prioritySend(newTileBatch, batch_id);
            				}
						}
					},
					/// handle request to (down)load tile image
					(size_t batch_id, int x, int y, int zoom)
					{
						if(batch_id < current_batch_id)  // ignore tile of previous requests
			            {
			            	return;
			            }

			            // check cache for given tile
			            shared(Tile) shared_tile;
			            auto layerx = tile_cache.get(x, null);
			            if(layerx !is null)
			            {
			            	auto layerxy = layerx.get(y, null);
			            	if(layerxy !is null)
			            		shared_tile = layerxy.get(zoom, null);
			            }
			            // if given tile found send it and quit
			            if(shared_tile !is null)
			            {
							frontend.send(batch_id, shared_tile);
			            	return;
			            }

						// if tile not found readress the request to one of workers
						auto current_tid = workers[current_worker];
	                    try
						{
							current_tid.send(batch_id, x, y, zoom, cache_path, url);
		                    current_worker++;
		                    if(current_worker == maxWorkers)
		                        current_worker = 0;
						}
						catch(LinkTerminated lt)
						{
							// just ignore it
							debug writeln("Child terminated");
	            		}
	            	},
		            // collect results from workers
	                (size_t batch_id, shared(Tile) shared_tile, int x, int y, int zoom) {
	                    if(batch_id != current_batch_id)  // ignore tile of other requests
	                        return;

	                    // store given tile into cache
	                    if(x !in tile_cache)
	                    	tile_cache[x] = (shared(Tile)[int][int]).init;
	                    if(y !in tile_cache[x])
	                    	tile_cache[x][y] = (shared(Tile)[int]).init;
	                    tile_cache[x][y][zoom] = shared_tile;

	                    tile_cache_content.insertFront(TileDescription(x, y, zoom));
	                    tile_cache_size++;
	                    if(tile_cache_size > maxTileCacheSize)
	                    {
	                    	enum tileAmountToFree = 64;
	                    	foreach(i; 0..tileAmountToFree)
	                    	{
	                    		auto description = tile_cache_content.back;
	                    		tile_cache[description.x][description.y][description.zoom] = null;
	                    		tile_cache_content.removeBack();
	                    	}
	                    	tile_cache_size -= tileAmountToFree;
		                }

	                    // translate tile to frontend
	                    frontend.send(batch_id, shared_tile);
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

	enum newTileBatch = "new tile batch";

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
