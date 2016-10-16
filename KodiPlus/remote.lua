local tid = -1;
local data = libs.data;
local http = libs.http;
local log = libs.log;
local server = libs.server;
local timer = libs.timer;
local old_title = "";

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

events.focus = function()
	host = settings.host;
	port = settings.port;
	username = settings.username;
	password = settings.password;
	volume_step = settings.volume_step;
	old_title = "";
	
	if (test()) then
		update_info();
	end
end

events.blur = function()
	timer.cancel(tid);
end

function test()
	-- Verify that Kodi is accessible otherwise show some nice help information
	local resp = send("JSONRPC.Version");
	if (resp == nil) then
		server.update({
			type = "dialog",
			title = "Kodi Connection",
			text = "A connection to Kodi could not be established." ..
				"We recommend using the latest version of Kodi.\n\n" ..
				"1. Make sure Kodi is running on your computer.\n\n" ..
				"2. Enable the Webserver in System > Settings > Services > Allow control of Kodi via HTTP\n\n" ..
				"3. Unified Remote is pre-configured to use port 8080 and no password.\n\n" ..
				"You may have to restart Kodi after enabling the web interface for the changes to take effect.",
			children = {{ type = "button", text = "OK" }}
		});
		return false;
	else
		return true;
	end
end

------------------------------------------------------------------------
-- Web Request
------------------------------------------------------------------------

function send(method, params)
	local req = {};
	req.jsonrpc = "2.0";
	req.id = 1;
	if (method ~= nil) then req.method = method; end
	if (params ~= nil) then req.params = params; end
	
	-- Send a JSON-RPC request
	local host = settings.host;
	local port = settings.port;
	local url = "http://" .. host .. ":" .. port .. "/jsonrpc";
	-- local ok = true;
	local json = data.tojson(req);
	local headers = {Authorization = "Basic " .. data.tobase64(settings.username .. ":" .. settings.password)}
	local ok, resp = pcall(http.request,{
		method = "post",
		url = url,
		mime = "application/json",
		headers = headers,
		content = json
	});
	if (ok and resp ~= nil and resp.status == 200) then
		return data.fromjson(resp.content);
	else
		server.update({ id = "title", text = "[Not Connected]" });
		return nil;
	end
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------

function update_info()
	local pid = player();
	local current_title = "";
	
	if (pid == nil) then
		server.update(
			{ id = "title", text = get_title() },
			{ id = "cover", image = "" },
			{ id = "pos_slider", text = "", progress = 0, progressmax = 0 }
		);
	else
		local current_item = get_current_item();
		
		current_title = get_title();
		if (current_title ~= old_title) then
			local cover_url = get_cover_url(prepare_download(current_item.thumbnail));
			
			old_title = current_title;
			server.update(
				{ id = "title", text = current_item.label },
				{ id = "cover", image = cover_url }
			);
		end
		
		server.update(
			{ id = "pos_slider", progress = get_percentage(), progressmax = 100 }
		);
	end
	
	-- check and update volume level even if there is nothing playing
	server.update(
		{ id = "vol_slider", progress = get_volume() }
	);
	
	tid = timer.timeout(update_info, 1000);
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

--@help Launch Kodi application
actions.launch = function()
	if OS_WINDOWS then
		os.start("%programfiles(x86)%\\Kodi\\Kodi.exe");
	elseif OS_OSX then
		os.script("tell application \"Kodi\" to activate");
	end
end

function player()
	local resp = send("Player.GetActivePlayers");
	if (resp == nil) then
		print("Check your settings for Kodi. Possibly wrong port or password, username");
	else
		if (resp.result[1] == nil) then
			return nil;
		else
			return resp.result[1].playerid;
		end
	end
end

function input(key)
	send("Input." .. key);
end

function get_volume()
	local resp = send("Application.GetProperties", { properties = { "volume" } });
	return resp.result.volume;
end

--@help Toggle play/pause
actions.play_pause = function()
	send("Player.PlayPause", { playerid = player() });
end

--@help Stop playback
actions.stop = function()
	send("Player.Stop", { playerid = player() });
end

--@help Play next item
actions.next = function()
	send("Player.GoNext", { playerid = player() });
end

--@help Play previous item
actions.previous = function()
	send("Player.GoPrevious", { playerid = player() });
end

--@help Rewind
actions.rewind = function()
	send("Player.SetSpeed", { playerid = player(), speed = "decrement" });
end

--@help Fast forward
actions.forward = function()
	send("Player.SetSpeed", { playerid = player(), speed = "increment" });
end

--@help Set volume level
--@param vol:number Volume level (0-100)
actions.set_volume = function(vol)
	if (vol > 100) then vol = 100; end
	if (vol < 0) then vol = 0; end
	send("Application.SetVolume", { volume = vol });
	server.update({ id = "vol_slider", progress = vol });
end

--@help Raise volume
actions.volume_up = function()
	actions.set_volume(get_volume() + settings.volume_step);
end

--@help Lower volume
actions.volume_down = function()
	actions.set_volume(get_volume() - settings.volume_step);
end

--@help Toggle mute volume
actions.volume_mute = function()
	send("Application.SetMute", { mute = "toggle" });
end

--@help Navigate left
actions.left = function()
	input("Left");
end

--@help Navigate right
actions.right = function()
	input("Right");
end

--@help Navigate up
actions.up = function()
	input("Up");
end

--@help Navigate down
actions.down = function()
	input("Down");
end

--@help Select current item
actions.select = function()
	input("Select");
end

--@help Navigate back
actions.back = function()
	input("Back");
end

--@help Toggle context menu
actions.menu = function()
	input("ContextMenu");
end

--@help Toggle OSD
actions.osd = function()
	input("ShowOSD");
end

--@help Navigate home
actions.home = function()
	input("Home");
end

--@help Toggle information
actions.info = function()
	input("Info");
end

--@help Toggle fullscreen
actions.fullscreen = function()
	send("GUI.SetFullscreen", { fullscreen = "toggle" });
end

--@help Toggle subtitles
actions.subtitles = function()
	send("Input.ExecuteAction", { action = "showsubtitles" });
end

--@help Change position
actions.seek = function(percentage)
	send("Player.Seek", { playerid = player(), value = percentage });
end

------------------------------------------------------------------------
-- Information
------------------------------------------------------------------------

--@help Get currently playing item
function get_current_item()
	local resp = send("Player.GetItem", { playerid = player(), properties = { "thumbnail" } });
	return resp.result.item;
end

--@help Get title of currently playing item
function get_title()
	if (player() ~= nil) then
		return get_current_item().label;
	else
		return "[Not Playing]";
	end
end

--@help Tell Kodi to prepare the file for download
--@param url:string The URL for the item to download
function prepare_download(url)
	local resp = send("Files.PrepareDownload", { path = url });
	
	return resp.result.details.path;
end

--@help Get title of currently playing item
--@param url:string The URL for the item to download
function get_cover_url(url)
	local is_local = true;
	if (is_local) then
		local host = settings.host;
		local port = settings.port;
		local username = settings.username;
		local password = settings.password;
		
		-- TODO: This is still sort of a hack. Improve this.
		return string.format("http://%s:%s@%s:%s/%s", username, password, host, port, url);
	else
		return nil;
	end
end

--@help Get percentage of currently playing item
function get_percentage()
	local resp = send("Player.GetProperties", { playerid = player(), properties = { "percentage" } });
	
	return math.floor(resp.result.percentage + 0.5);
end
