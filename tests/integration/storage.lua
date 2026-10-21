package.path='./src/?.lua;'..package.path
local uv=require('luv')
local store=require('store')
local dir=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/profile history.XXXXXX'))
local function record(id) return {schema='performance-history/v1',kind='observation',project='first_project',id=id,datetime_utc='2026-10-02T12:00:00.001Z',eligible=false} end
local s=store.open('file://'..dir,'first_project')
assert(s:write(record('run1'))=='created')
assert(s:write(record('run1'))=='exists')
local r=record('run1'); r.eligible=true
assert(not pcall(function() s:write(r) end),'conflicting identity must not overwrite')
local files=assert(uv.fs_scandir(dir))
assert(uv.fs_scandir_next(files)=='first_project--observation--run1.ndjson','project name missing from filename')
local other=store.open('file://'..dir,'second_project')
local second=record('run1'); second.project='second_project'; other:write(second)
assert(#s:read()==1 and #other:read()==1,'project namespaces mixed')
local file=assert(io.open(dir..'/first_project--observation--broken.ndjson','w')); file:write('{bad\n'); file:close()
assert(not pcall(function() s:read() end),'malformed history silently ignored')
assert(uv.fs_unlink(dir..'/first_project--observation--broken.ndjson'))
local outsider=dir..'/outsider'; file=assert(io.open(outsider,'w')); file:write('unmodified'); file:close()
assert(uv.fs_symlink(outsider,dir..'/first_project--observation--link.ndjson'))
assert(not pcall(function() s:write(record('link')) end),'symlink was followed')
assert(not pcall(function() store.open('https://example.com','p') end))
assert(not pcall(function() store.open('file://relative','p') end))
assert(not pcall(function() store.open('file://'..dir,'../escape') end))
local good=store.open('file://'..dir,'safe')
local ok=record('unique'); ok.project='safe'; good:write(ok)
assert(#good:read()==1)
assert(not pcall(function() store.open('file://'..dir,'first_project--observation') end),'ambiguous filename namespace accepted')
local pending=assert(io.open(dir..'/.pending-interrupted','wb')); pending:write('{partial'); pending:close()
assert(#good:read()==1,'interrupted temp file entered history')
assert(uv.fs_chmod(dir,tonumber('500',8)))
local denied=record('denied'); denied.project='safe'
assert(not pcall(function() good:write(denied) end),'read-only directory admitted a write')
assert(uv.fs_chmod(dir,tonumber('700',8)))
-- Latency records live in their own filename namespace, <project>.latency--<id>.ndjson,
-- which the cg/mg reader's '<project>--' prefix never matches: engines that
-- predate latency records keep reading a shared directory unchanged.
do
	local ldir=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/latency history.XXXXXX'))
	local ls=store.open('file://'..ldir,'first_project')
	assert(ls:write(record('obs'))=='created')
	local lat={schema='performance-latency/v1',kind='latency',project='first_project',id='job1',datetime_utc='2026-10-20T12:00:00.000Z',comparable=true}
	assert(ls:write_latency(lat)=='created')
	assert(ls:write_latency(lat)=='exists','identical latency rerun must be a no-op')
	local changed={}; for k,v in pairs(lat) do changed[k]=v end; changed.comparable=false
	assert(not pcall(function() ls:write_latency(changed) end),'conflicting latency record overwrote')
	assert(uv.fs_lstat(ldir..'/first_project.latency--job1.ndjson'),'latency filename namespace')
	local cg=ls:read()
	assert(#cg==1 and cg[1].kind=='observation','cg/mg reader saw latency records')
	local lr=ls:read_latency()
	assert(#lr==1 and lr[1].kind=='latency','latency reader saw cg/mg records')
	assert(not pcall(function() ls:write_latency(record('wrong')) end),'cg/mg record accepted as latency')
	assert(not pcall(function() ls:write(lat) end),'latency record accepted as cg/mg')
	local other=store.open('file://'..ldir,'first')
	assert(#other:read_latency()==0 and #other:read()==0,'project prefix leaked between namespaces')
end
print('PASS: atomic history, namespace, idempotency and corruption adapters')
