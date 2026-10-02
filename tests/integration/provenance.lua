package.path='./src/?.lua;'..package.path
local uv=require('luv')
local process=require('process')
local provenance=require('provenance')
local config=require('config')
local root=assert(uv.fs_mkdtemp((os.getenv('TMPDIR') or '/tmp')..'/provenance.XXXXXX'))
local function write(path,body)
	local f=assert(io.open(root..'/'..path,'wb')); assert(f:write(body)); assert(f:close())
end
write('settings.toml','enabled=true\n')
write('.settings','hidden=true\n')
write('fixture.txt','original input\n')
write('kernel.lua','return 1\n')
process.checked({'git','-C',root,'init','-q','-b','yolo'})
process.checked({'git','-C',root,'add','.'})
process.checked({'git','-C',root,'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'})
local cfg=config.validate({schema='performance-project/v1',project='fixture',history_url='file:///tmp/outside',identity={runtime='test',build_mode='optimized',concurrency=1},cases={{cores=1,name='linear',mode='cg',metric='operations',sizes={1,2},bounds={1,4},command={'luajit','kernel.lua'}}}})
local before=provenance.snapshot(root,cfg)
for _,path in ipairs({'settings.toml','.settings','fixture.txt'}) do
	write(path,'changed relevant input\n')
	local after,metadata=provenance.snapshot(root,cfg)
	assert(after~=before,'excluded-statistics file did not change source identity: '..path)
	assert(#metadata.git.dirty_code==0,'non-code file leaked into dirty-code statistics')
	before=after
end
write('kernel.lua','return 2\n')
local after,metadata=provenance.snapshot(root,cfg)
assert(after~=before and #metadata.git.dirty_code==1 and metadata.git.dirty_code[1].added==1 and metadata.git.dirty_code[1].deleted==1)
-- Single-core and multicore measurements never share a cohort, and the
-- cohort says how many cores and how they were enforced.
local one_cohort,one_hw=provenance.identity(cfg,cfg.cases[1])
local multi=setmetatable({cores=12},{__index=cfg.cases[1]})
local multi_cohort,multi_hw=provenance.identity(cfg,multi)
assert(one_cohort~=multi_cohort,'1-core and 12-core cases shared a cohort')
assert(one_hw.cores==1 and multi_hw.cores==12,'core count not recorded in the cohort')
assert(one_hw.affinity=='taskset' or one_hw.affinity=='unenforced','affinity method not recorded')
print('PASS: configuration/fixture identity remains distinct from code-only statistics; cores separate cohorts')
