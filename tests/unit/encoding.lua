package.path='./src/?.lua;'..package.path
local enc=require('encoding')
local bytes={}; for i=0,255 do bytes[#bytes+1]=string.char(i) end
local binary=table.concat(bytes)
assert(enc.decode(enc.encode(binary))==binary)
local seen={}
for i=0,255 do
	local encoded=enc.encode(string.char(i))
	assert(not seen[encoded],'mapping collision between source bytes')
	seen[encoded]=true
	assert(enc.decode(encoded)==string.char(i),'one-byte inverse mismatch')
	assert(enc.encode(enc.decode(encoded))==encoded,'target inverse mismatch')
end
local output=enc.encode('a path\nwith "quotes"\tand\\slashes')
assert(output:find('a path',1,true) and not output:find('[\n\t]'))
local json=require('json')
assert(json.decode(json.encode({value=output})).value==output)
assert(enc.map_sha256:match('^[a-f0-9]+$') and #enc.map_sha256==64)
print('PASS: pinned printable-binary all-byte round trip and NDJSON safety')
