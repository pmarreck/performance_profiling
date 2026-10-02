package.path='./src/?.lua;'..package.path
local uv=require('luv')
local json=require('json')
local store=require('store')
local dir=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/profile-concurrent.XXXXXX'))
local child=[[
package.path='./src/?.lua;'..package.path
local r=require('json').decode(arg[1])
local s=require('store').open(arg[0],r.project)
io.write(s:write(r))
os.exit(0)
]]
local function batch(shared)
	local results={}
	for i=1,8 do
		local r={schema='performance-history/v1',kind='observation',project='concurrent',id=shared and 'same' or 'distinct'..i,datetime_utc='2026-10-02T13:00:00.001Z',eligible=false}
		local stdout,stderr=uv.new_pipe(false),uv.new_pipe(false)
		local entry={stdout='',stderr=''}; results[i]=entry
		local handle
		handle=assert(uv.spawn('luajit',{args={'-e',child,'--','file://'..dir,json.encode(r)},stdio={nil,stdout,stderr}},function(code) entry.rc=code; handle:close() end))
		for _,p in ipairs({{stdout,'stdout'},{stderr,'stderr'}}) do
			uv.read_start(p[1],function(e,data)
				assert(not e,e)
				if data then entry[p[2]]=entry[p[2]]..data else p[1]:close() end
			end)
		end
	end
	uv.run()
	local created=0
	for _,r in ipairs(results) do assert(r.rc==0,r.stderr); assert(r.stderr==''); if r.stdout=='created' then created=created+1 else assert(r.stdout=='exists') end end
	assert(created==(shared and 1 or 8),'atomic publication count differs')
end
batch(true); batch(false)
local history=store.open('file://'..dir,'concurrent'):read()
assert(#history==9,'concurrent writes lost or duplicated records')
print('PASS: simultaneous same-ID and distinct-ID history writers')
