package.path='./src/?.lua;'..package.path
local runner=require('runner')
local json=require('json')
local cfg=require('config').validate({schema='performance-project/v1',project='fixture',history_url='file:///tmp/outside',identity={runtime='test',build_mode='optimized',concurrency=1},cases={{cores=1,name='linear',mode='cg',metric='cpu_ns',command={'bench'},sizes={10,20},bounds={1,4}}}})
local function m(mult)
	return {schema='performance-measurement/v1',correct=true,build_mode='optimized',rows={{size=10,samples={cpu_ns={10,10,10}}},{size=20,samples={cpu_ns={20*mult,20*mult,20*mult}}}}}
end
local calls,writes,records=0,{},{}
local adapter={records=function() return records end,write=function(r) writes[#writes+1]=r; records[#records+1]=r end,
	measure=function() calls=calls+1; return m(1) end,identity=function() return 'cohort',{} end,
	snapshot=function() return 'source',{} end,now=function() return '2026-10-02T12:00:00.001Z' end,id=function() return 'id'..(#writes+1) end}
local rows=runner.run(cfg,{mode='cg',seed='fixed'},adapter)
assert(rows[1].verdict=='UNBASELINED' and not rows[1].eligible and #writes==1)
runner.accept(cfg,rows[1].id,'independent work check reviewed',adapter)
assert(writes[2].kind=='approval')
rows=runner.run(cfg,{mode='cg',seed='fixed'},adapter)
assert(rows[1].verdict=='PASS' and rows[1].epoch==writes[2].id and rows[1].eligible)
local n=0
adapter.measure=function() n=n+1; return m(n==1 and 1.25 or 1) end
rows=runner.run(cfg,{mode='cg'},adapter)
assert(rows[1].verdict=='PASS_ON_RETRY' and #rows[1].diagnostics==1)
assert(rows[1].selected.ratios[1]==2 and rows[1].diagnostics[1].ratios[1]==2.5)
assert(not pcall(runner.accept,cfg,rows[1].id,'',adapter))
rows=runner.run(cfg,{mode='cg',seed='fixed',run_id='stable-job'},adapter)
local before=calls
local count=#writes
local repeated=runner.run(cfg,{mode='cg',seed='fixed',run_id='stable-job'},adapter)
assert(repeated[1].id==rows[1].id and #writes==count and calls==before,'completed logical run duplicated effects')
assert(not pcall(runner.run,cfg,{mode='cg',seed='changed',run_id='stable-job'},adapter),'conflicting logical run accepted')
adapter.identity=function() return 'different-cpu',{} end
assert(not pcall(runner.run,cfg,{mode='cg',seed='fixed',run_id='stable-job'},adapter),'logical run reused on different hardware')
adapter.identity=function() return 'cohort',{} end
-- A changed source cannot be admitted even when a benchmark reported a pass.
local snap=0
adapter.snapshot=function() snap=snap+1; return snap==1 and 'before' or 'after',{} end
rows=runner.run(cfg,{mode='cg'},adapter)
assert(rows[1].verdict=='INVALID' and not rows[1].eligible)
-- The source is snapshotted once before the first case and once after the
-- last, not around every case (hashing a large tree per case dominated short
-- gates), and a change anywhere in the run invalidates every case of it.
do
	local three=require('config').validate({schema='performance-project/v1',project='fixture',history_url='file:///tmp/outside',identity={runtime='test',build_mode='optimized',concurrency=1},cases={
		{cores=1,name='a',mode='cg',metric='cpu_ns',command={'bench'},sizes={10,20},bounds={1,4}},
		{cores=1,name='b',mode='cg',metric='cpu_ns',command={'bench'},sizes={10,20},bounds={1,4}},
		{cores=1,name='c',mode='cg',metric='cpu_ns',command={'bench'},sizes={10,20},bounds={1,4}}}})
	local snaps=0
	local three_adapter=setmetatable({snapshot=function() snaps=snaps+1; return 'same',{} end,measure=function() return m(1) end,records=function() return {} end,write=function() end},{__index=adapter})
	runner.run(three,{mode='cg'},three_adapter)
	assert(snaps==2,'expected one snapshot before and one after the run, got '..snaps)
	snaps=0
	three_adapter.snapshot=function() snaps=snaps+1; return snaps==1 and 'before' or 'after',{} end
	local changed=runner.run(three,{mode='cg'},three_adapter)
	for _,r in ipairs(changed) do assert(r.verdict=='INVALID' and not r.eligible,'case '..r.case..' kept despite a source change during the run') end
end
-- History writes must not be silently skipped on errors.
adapter.write=function() error('storage denied') end
assert(not pcall(runner.run,cfg,{mode='cg'},adapter))
print('PASS: injected measurement, approval, source consistency and persistence')
