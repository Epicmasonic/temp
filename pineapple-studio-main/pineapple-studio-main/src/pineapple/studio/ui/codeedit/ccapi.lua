local raw = {}

raw._G = [[
print(...) Print values, then a new line. Returns the number of lines printed
write(text) Write text with word wrapping, no new line
printError(...) Print in red (on colour screens)
read(replaceChar, history, completeFn, default) Read a line of text typed by the user
sleep(seconds) Pause for a number of seconds
require(name) Load a module from package.path
dofile(path) Run a Lua file and return its results
loadfile(path, mode, env) Load a file as a function without running it
load(chunk, name, mode, env) Load a string or function as a Lua chunk
pcall(fn, ...) Call fn, catching errors: ok, results...
xpcall(fn, handler, ...) Call fn with an error handler
error(message, level) Raise an error
assert(value, message) Error if value is false or nil
type(value) Name of a value's type
tostring(value) Convert a value to a string
tonumber(value, base) Convert a value to a number, or nil
pairs(t) Iterate over all keys of a table
ipairs(t) Iterate over t[1], t[2]... until nil
next(t, key) Next key and value of a table
select(n, ...) Arguments from n on; select("#", ...) counts them
rawget(t, key) Get without metamethods
rawset(t, key, value) Set without metamethods
rawequal(a, b) Compare without metamethods
rawlen(t) Length without metamethods
setmetatable(t, metatable) Set a table's metatable
getmetatable(value) A value's metatable
_G The global environment
_HOST Host and version string
]]

raw.term = [[
write(text) Write text at the cursor, without wrapping
blit(text, textColours, backgroundColours) Write text with a colour per character (blit hex strings)
clear() Clear the screen with the background colour
clearLine() Clear the line the cursor is on
getCursorPos() Cursor position: x, y
setCursorPos(x, y) Move the cursor
getCursorBlink() Whether the cursor blinks
setCursorBlink(blink) Show or hide the blinking cursor
isColour() Whether the terminal supports colour
isColor() Whether the terminal supports colour
getSize() Terminal size: width, height
scroll(y) Scroll the screen up by y lines
redirect(target) Draw on another terminal object; returns the previous one
current() The terminal currently drawn on
native() The computer's own screen
setTextColour(colour) Colour for text written next
setTextColor(colour) Colour for text written next
getTextColour() Current text colour
getTextColor() Current text colour
setBackgroundColour(colour) Background colour for text written next
setBackgroundColor(colour) Background colour for text written next
getBackgroundColour() Current background colour
getBackgroundColor() Current background colour
setPaletteColour(colour, r, g, b) Change a palette entry (0-1 or one 0xRRGGBB number)
setPaletteColor(colour, r, g, b) Change a palette entry (0-1 or one 0xRRGGBB number)
getPaletteColour(colour) A palette entry: r, g, b
getPaletteColor(colour) A palette entry: r, g, b
nativePaletteColour(colour) Default palette entry: r, g, b
nativePaletteColor(colour) Default palette entry: r, g, b
]]

raw.fs = [[
list(path) Names of the files and folders in a folder
exists(path) Whether a path exists
isDir(path) Whether a path is a folder
isReadOnly(path) Whether a path can't be written
getName(path) Last part of a path
getDir(path) Path without its last part
getSize(path) Size of a file in bytes
getFreeSpace(path) Free space on the drive
getCapacity(path) Capacity of the drive
makeDir(path) Create a folder (and its parents)
move(from, to) Move or rename a file or folder
copy(from, to) Copy a file or folder
delete(path) Delete a file or folder
combine(path, ...) Join path parts
open(path, mode) Open a file: "r", "w", "a", "rb", "wb", "ab" (+ for update)
find(pattern) Paths matching a wildcard pattern
complete(partial, dir, includeFiles, includeDirs) Completions for a partial path
getDrive(path) Name of the drive a path is on
attributes(path) size, isDir, isReadOnly, created, modified
isDriveRoot(path) Whether a path is the root of a drive
]]

raw.os = [[
version() CraftOS version string
getComputerID() This computer's ID
computerID() This computer's ID
getComputerLabel() This computer's label, or nil
computerLabel() This computer's label, or nil
setComputerLabel(label) Set or clear the label
run(env, path, ...) Run a program with an environment
pullEvent(filter) Wait for an event: name, ...
pullEventRaw(filter) Like pullEvent, but also returns terminate events
queueEvent(name, ...) Add an event to the queue
startTimer(seconds) Start a timer; a "timer" event with its ID fires later
cancelTimer(id) Cancel a timer
setAlarm(time) Alarm at an in-game time; fires an "alarm" event
cancelAlarm(id) Cancel an alarm
clock() Seconds since the computer started
time(locale) Time: in-game hours, or "utc"/"local"
day(locale) Day: in-game, or "utc"/"local"
epoch(locale) Milliseconds since an epoch ("ingame", "utc", "local")
date(format, time) Formatted date, like Lua's os.date
sleep(seconds) Pause for a number of seconds
shutdown() Turn the computer off
reboot() Restart the computer
loadAPI(path) Load a file as a global API (deprecated: use require)
unloadAPI(name) Remove a global API
]]

raw.colors = [[
white 1
orange 2
magenta 4
lightBlue 8
yellow 16
lime 32
pink 64
gray 128
lightGray 256
cyan 512
purple 1024
blue 2048
brown 4096
green 8192
red 16384
black 32768
combine(...) Combine colours into a set (bitwise or)
subtract(colours, ...) Remove colours from a set
test(colours, colour) Whether a set contains a colour
packRGB(r, g, b) Pack 0-1 components into 0xRRGGBB
unpackRGB(rgb) Unpack 0xRRGGBB into r, g, b
toBlit(colour) Blit character (0-f) for a colour
fromBlit(hex) Colour for a blit character
]]
raw.colours = (raw.colors:gsub("gray", "grey"))

raw.peripheral = [[
getNames() Names of attached peripherals
isPresent(name) Whether a peripheral is attached
getType(peripheral) Type(s) of a peripheral
hasType(peripheral, type) Whether a peripheral has a type
getMethods(name) Method names of a peripheral
getName(peripheral) Name of a wrapped peripheral
call(name, method, ...) Call a peripheral method
wrap(name) Table of a peripheral's methods
find(type, filter) Wrapped peripherals of a type
]]

raw.rednet = [[
open(modem) Open a modem for rednet
close(modem) Close a modem (or all)
isOpen(modem) Whether a modem (or any) is open
send(recipient, message, protocol) Send a message to a computer ID
broadcast(message, protocol) Send a message to every computer
receive(protocol, timeout) Wait for a message: sender, message, protocol
host(protocol, hostname) Register this computer for lookup
unhost(protocol) Stop hosting a protocol
lookup(protocol, hostname) Find computers hosting a protocol
run() Rednet's background loop (started by the OS)
CHANNEL_BROADCAST Channel for broadcasts
CHANNEL_REPEAT Channel used by repeaters
]]

raw.redstone = [[
getSides() Side names: top, bottom, left, right, front, back
setOutput(side, on) Turn redstone output on or off
getOutput(side) Whether output is on
getInput(side) Whether input is on
setAnalogOutput(side, value) Output strength 0-15
getAnalogOutput(side) Output strength
getAnalogInput(side) Input strength 0-15
setBundledOutput(side, colours) Bundled cable output
getBundledOutput(side) Bundled cable output
getBundledInput(side) Bundled cable input
testBundledInput(side, mask) Whether bundled input has the colours in mask
]]
raw.rs = raw.redstone

raw.textutils = [[
slowWrite(text, rate) Write text a character at a time
slowPrint(text, rate) Print text a character at a time
formatTime(time, twentyFourHour) Format a time from os.time
pagedPrint(text, freeLines) Print, pausing every screen
tabulate(...) Print tables of strings in columns
pagedTabulate(...) Like tabulate, pausing every screen
serialize(value, options) Value as a Lua string
serialise(value, options) Value as a Lua string
unserialize(text) Parse a serialized string
unserialise(text) Parse a serialised string
serializeJSON(value, options) Value as JSON
serialiseJSON(value, options) Value as JSON
unserializeJSON(text, options) Parse JSON
unserialiseJSON(text, options) Parse JSON
urlEncode(text) Encode a string for URLs
complete(text, searchTable) Completions for a Lua expression
empty_json_array Value serialised as []
json_null Value serialised as null
]]

raw.http = [[
request(url, body, headers, binary) Start a request; http_success or http_failure event follows
get(url, headers, binary) GET a URL: response handle, or nil and an error
post(url, body, headers, binary) POST to a URL: response handle, or nil and an error
checkURL(url) Whether a URL may be requested
checkURLAsync(url) Check a URL; http_check event follows
websocket(url, headers) Open a websocket
websocketAsync(url, headers) Open a websocket; websocket_success event follows
]]

raw.parallel = [[
waitForAny(...) Run functions together until one finishes
waitForAll(...) Run functions together until all finish
]]

raw.window = [[
create(parent, x, y, width, height, visible) A window: a terminal inside another terminal
]]

raw.paintutils = [[
parseImage(image) Parse an image from a string
loadImage(path) Load an image file
drawPixel(x, y, colour) Draw one pixel
drawLine(startX, startY, endX, endY, colour) Draw a line
drawBox(startX, startY, endX, endY, colour) Draw a box outline
drawFilledBox(startX, startY, endX, endY, colour) Draw a filled box
drawImage(image, x, y) Draw an image
]]

raw.shell = [[
run(...) Run a program with arguments
execute(command, ...) Run a program, without parsing the command line
exit() Exit the shell
dir() Current folder
setDir(dir) Change the current folder
path() Program search path
setPath(path) Change the program search path
resolve(path) Absolute path from a relative one
resolveProgram(command) Path of a program
programs(includeHidden) Program names on the path
complete(line) Completions for a command line
completeProgram(program) Completions for a program name
setCompletionFunction(program, complete) Argument completion for a program
getCompletionInfo() Registered completion functions
getRunningProgram() Path of the running program
setAlias(command, program) Add an alias
clearAlias(command) Remove an alias
aliases() All aliases
openTab(...) Run a program in a new multishell tab
switchTab(id) Switch to a multishell tab
]]

raw.multishell = [[
getFocus() ID of the focused tab
setFocus(id) Focus a tab
getTitle(id) Title of a tab
setTitle(id, title) Set a tab's title
getCurrent() ID of this program's tab
launch(env, path, ...) Start a program in a new tab
getCount() Number of tabs
]]

raw.settings = [[
define(name, options) Declare a setting: description, default, type
undefine(name) Remove a declaration
set(name, value) Set a setting
get(name, default) Value of a setting
getDetails(name) Description, default, type and value
unset(name) Remove a value
clear() Remove all values
getNames() Names of all settings
load(path) Load settings from a file
save(path) Save settings to a file
]]

raw.gps = [[
locate(timeout, debug) Position from GPS hosts: x, y, z
CHANNEL_GPS Channel used by GPS
]]

raw.disk = [[
isPresent(name) Whether a disk is inserted
getLabel(name) Label of the disk
setLabel(name, label) Set the label of the disk
hasData(name) Whether the disk is a floppy
getMountPath(name) Where the disk is mounted
hasAudio(name) Whether the disk is a music disc
getAudioTitle(name) Title of the music disc
playAudio(name) Play the music disc
stopAudio(name) Stop playing
eject(name) Eject the disk
getID(name) ID of the floppy disk
]]

raw.vector = [[
new(x, y, z) A 3D vector
]]

raw.turtle = [[
forward() Move forward: ok, reason
back() Move back
up() Move up
down() Move down
turnLeft() Turn left
turnRight() Turn right
dig(side) Mine the block in front
digUp(side) Mine the block above
digDown(side) Mine the block below
place(text) Place the selected item in front
placeUp(text) Place above
placeDown(text) Place below
drop(count) Drop items in front
dropUp(count) Drop items above
dropDown(count) Drop items below
select(slot) Select an inventory slot (1-16)
getSelectedSlot() Selected slot
getItemCount(slot) Number of items in a slot
getItemSpace(slot) Space left in a slot
getItemDetail(slot, detailed) Item in a slot: name, count...
detect() Whether there's a block in front
detectUp() Whether there's a block above
detectDown() Whether there's a block below
compare() Whether the block in front matches the selected item
compareUp() Compare the block above
compareDown() Compare the block below
compareTo(slot) Whether a slot matches the selected one
attack(side) Attack in front
attackUp(side) Attack above
attackDown(side) Attack below
suck(count) Pick up items in front
suckUp(count) Pick up items above
suckDown(count) Pick up items below
getFuelLevel() Fuel left
getFuelLimit() Maximum fuel
refuel(count) Use the selected item as fuel
transferTo(slot, count) Move items to another slot
equipLeft() Equip the selected item on the left
equipRight() Equip the selected item on the right
inspect() Block in front: ok, data
inspectUp() Block above: ok, data
inspectDown() Block below: ok, data
craft(limit) Craft with the items in the inventory
]]

raw.pocket = [[
equipBack() Equip an upgrade from the inventory
unequipBack() Remove the upgrade
]]

raw.io = [[
write(...) Write to the current output
read(...) Read from the current input
lines(path, ...) Iterate over the lines of a file
open(path, mode) Open a file: handle, or nil and an error
close(file) Close a file
input(file) Get or set the current input
output(file) Get or set the current output
type(value) "file", "closed file" or nil
stdin Standard input
stdout Standard output
stderr Standard error
]]

raw.string = [[
byte(s, i, j) Character codes
char(...) String from character codes
find(s, pattern, init, plain) Position of a pattern: start, end, captures
format(format, ...) Formatted string (%d, %s, %q, %5.2f...)
gmatch(s, pattern) Iterate over pattern matches
gsub(s, pattern, replacement, n) Replace matches: result, count
len(s) Length
lower(s) Lower case
upper(s) Upper case
match(s, pattern, init) Captures of the first match
rep(s, n, separator) Repeat a string
reverse(s) Reversed string
sub(s, i, j) Substring
]]

raw.table = [[
concat(list, separator, i, j) Join list items into a string
insert(list, pos, value) Insert a value (at the end without pos)
remove(list, pos) Remove and return an item (the last without pos)
sort(list, comp) Sort a list in place
unpack(list, i, j) List items as separate values
pack(...) Arguments as a table with n
]]

raw.math = [[
abs(x) Absolute value
ceil(x) Round up
floor(x) Round down
max(x, ...) Largest value
min(x, ...) Smallest value
sqrt(x) Square root
random(m, n) Random number: 0-1, 1-m or m-n
randomseed(x) Seed the random generator
sin(x) Sine (radians)
cos(x) Cosine (radians)
tan(x) Tangent (radians)
asin(x) Arc sine
acos(x) Arc cosine
atan(y, x) Arc tangent
exp(x) e to the power x
log(x, base) Logarithm
fmod(x, y) Remainder of x / y
modf(x) Integer and fractional parts
deg(x) Radians to degrees
rad(x) Degrees to radians
huge Infinity
pi 3.14159...
]]

raw.coroutine = [[
create(fn) New coroutine
resume(co, ...) Start or continue a coroutine: ok, values...
yield(...) Pause the running coroutine
status(co) "running", "suspended", "normal" or "dead"
wrap(fn) Coroutine as a function
running() The running coroutine
isyieldable() Whether the running code can yield
]]

local M = {}
for module, text in pairs(raw) do
  local entries = {}
  for line in text:gmatch("[^\n]+") do
    local name, sig, doc = line:match("^([%w_]+)(%b())%s*(.*)$")
    if not name then
      name, doc = line:match("^([%w_]+)%s*(.*)$")
    end
    if name then entries[name] = { sig = sig, doc = doc ~= "" and doc or nil } end
  end
  M[module] = entries
end

return M
