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
-- Integers survive encoding exactly up to 2^53, including 16-digit monotonic
-- nanosecond timestamps that a 14-significant-digit format would round.
for _,n in ipairs({0,1,-1,99999999999999,100000000000000,2154390545095961,-2154390545095961,2^53-1,2^53}) do
	local text=json.encode({n=n})
	assert(json.decode(text).n==n,"integer did not round-trip: "..("%.0f"):format(n).." -> "..text)
	assert(not text:find("e",1,true),"integer written in exponent form: "..text)
end
assert(json.decode(json.encode(0.5))==0.5 and json.encode(0.5)=="0.5","fractions keep their form")
assert(enc.map_sha256:match('^[a-f0-9]+$') and #enc.map_sha256==64)
print('PASS: pinned printable-binary all-byte round trip and NDJSON safety')
