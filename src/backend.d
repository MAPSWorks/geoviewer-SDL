module backend;

import std.concurrency: spawn, send, prioritySend, Tid, thisTid, receiveTimeout, receiveOnly, spawnLinked, OwnerTerminated, LinkTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln, writefln;
import std.exception: enforce;
import std.conv: text;
import std.math: pow;
import std.container: DList;
import std.typecons: Tuple;
import std.file: exists, mkdirRecurse, dirName, read, write;
import std.path: buildNormalizedPath, absolutePath;

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

    static Tuple!(string, "path", string, "url") makeFullPathAndUrl(int x, int y, int zoom, string url, string local_path)
    {
        // wrap tile x, y
        auto n = pow(2, zoom);
        x = x % n;
        y = y % n;

        string absolute_path = absolutePath(local_path);
        auto filename = y.text ~ ".png";

        auto full_path = buildNormalizedPath(absolute_path, zoom.text, x.text, filename);
        auto full_url = url ? url ~ "/" ~ zoom.text ~ "/" ~ x.text ~ "/" ~ filename : "";
        return Tuple!(string, "path", string, "url")(full_path, full_url);
    }

    // parent is Tid of parent, id is unique identificator of child
    static void downloading(Tid parent, int id)
    {
        int zoom, x, y;
        x = y = zoom = -1;
        string path, url;
        auto running = true; // define it to let delegates below stop thread executing if needed
        size_t current_batch_id;

        // get tile batch id
        void handleTileBatchId(string text, size_t batch_id)
        {
            if(text == newTileBatch)
            {
                current_batch_id = batch_id;
            }
        }

        // get tile description to download
        void handleTileRequest(size_t batch_id, int local_x, int local_y, int local_zoom, string url, string path)
        {
            // use outer variable, see below catch construction
            x = local_x;
            y = local_y;
            zoom = local_zoom;
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

            auto tile = Tile.create(x, y, zoom, url, path);
            parent.send(batch_id, cast(shared) tile, x, y, zoom);
            x = y = zoom = -1;
        }

        try
        {
            DerelictFI.load();
            scope(exit) DerelictFI.unload();

            while(running)
            {
                auto msg = receiveTimeout(dur!"msecs"(100), // because this function is single in loop set delay big enough to lower processor loading
                    &handleTileBatchId,
                    &handleTileRequest,
                    (OwnerTerminated ot)
                    {
                        // normal exit
                        running = false;
                    }
                );
            }
        }
        catch(Throwable t)
        {
            debug writefln("thread id %s, throwable: %s", id, t.msg);
            debug writefln("on throwing x: %s, y: %s, zoom: %s", x, y, zoom);
            // complain to parent that something gone wrong
            parent.send(id, x, y, zoom);
        }
    }

	static run(string url, string cache_path)
	{
		enum maxWorkers = 8;
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

        // if x, y and zoom don't equal to -1 it means tile loading failed, child thread crashes
        // and parent can relaunch thread with the same zoom, x and y values to try loading once again.
        // If x, y or zoom equals to -1 it means that thread has crashed before valid x, y or zoom
        // recieving and parent can only restart thread without relaunching tile downloading
        void respawnWorker(int id, int x, int y, int zoom)
        {
            enforce(id >= 0 && id < maxWorkers);
            workers[id] = spawnLinked(&downloading, thisTid, id);
            debug writefln("thread respawned, id: %s", id);
            // relaunch tile downloading if there is valid info
            if(x != -1 && y != -1 && zoom != -1)
            {
                workers[id].send(x, y, zoom, cache_path, url);
                debug writefln("tile downloading restarted, x: %s, y: %s, zoom: %s", x, y, zoom);
            }
        }

        // set new tile batch with batch_id
        void setNewTileBatch(string text, size_t batch_id)
        {
            if(text == newTileBatch)
            {
                current_batch_id = batch_id;
                foreach(w; workers)
                {
                    w.prioritySend(newTileBatch, batch_id);
                }
            }
        }

        /// handle request to (down)load tile image
        void startTileDownloading(size_t batch_id, int x, int y, int zoom)
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
            auto full = makeFullPathAndUrl(x, y, zoom, url, cache_path);
            auto dir = dirName(full.path);
            if(!exists(dir))
                mkdirRecurse(dir); // it's better to create dirs in one parent thread instead of each of workers
            current_tid.send(batch_id, x, y, zoom, full.url, full.path);
            current_worker++;
            if(current_worker == maxWorkers)
                current_worker = 0;
        }

        // collect results from workers
        void getDownloadedTile(size_t batch_id, shared(Tile) shared_tile, int x, int y, int zoom) {
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
        }

		try
		{
			// prepare workers
	        foreach(int id; 0..maxWorkers)
                workers[id] = spawnLinked(&downloading, thisTid, id);

			// talk to child threads
	        bool msg;
	        bool running = true;
	        do{
	            msg = receiveTimeout(dur!"msecs"(10),
                    &respawnWorker,
					&setNewTileBatch,
					&startTileDownloading,
		            &getDownloadedTile,
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
		catch(Throwable t)
		{
			writefln("Backend premature finished its execution because of:\n%s", t.msg);
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
}
