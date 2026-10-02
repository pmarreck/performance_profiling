package.path='./src/?.lua;'..package.path
local config=require('config')
local core=require('core')
local cfg={schema='performance-project/v1',project='pilot',history_url='file:///tmp/history',identity={runtime='LuaJIT',build_mode='optimized',concurrency=1},cases={{cores=1,name='linear',mode='cg',metric='operations',command={'echo','{case}','{sizes}','{seed}',''},sizes={10,20,40,80},bounds={1.8,2.2}}}}
local original=cfg
cfg=config.validate(cfg)
assert(not original.cases[1].policy,'validation mutated caller-owned configuration')
assert(config.history_url(cfg,{}, {})=='file:///tmp/history')
assert(config.history_url(cfg,{}, {PERFORMANCE_HISTORY_URL='file:///tmp/env'})=='file:///tmp/env')
assert(config.history_url(cfg,{history_url='file:///tmp/cli'}, {PERFORMANCE_HISTORY_URL='file:///tmp/env'})=='file:///tmp/cli')
local c=cfg.cases[1]
local args=config.command(c,'27')
assert(args[2]=='linear' and args[3]=='10,20,40,80' and args[4]=='27' and args[5]=='')
c.sizes={10,20,41,80}; assert(not pcall(config.validate,cfg))
c.sizes={10,20,40,80}; c.policy.percent=-2; assert(not pcall(config.validate,cfg))
c.policy.percent=10; cfg.project='../../bad'; assert(not pcall(config.validate,cfg))
cfg.project='pilot'; cfg.identity.concurrency=0
assert(not pcall(config.validate,cfg),'zero concurrency accepted')
cfg.identity.concurrency=1; c.metric='startup_ns'
assert(not pcall(config.validate,cfg),'startup without readiness contract accepted')
c.comparison='absolute'; c.sizes={1}; c.ready_marker='ready\nextra'
assert(not pcall(config.validate,cfg),'multiline marker accepted')
c.ready_marker='ready'
assert(pcall(config.validate,cfg),'valid startup contract rejected')
c.command[1]=''
assert(not pcall(config.validate,cfg),'empty executable accepted')
c.command[1]='echo'; c.metric='operations'; c.comparison='growth'; c.sizes={10,20,40,80}
local approve={schema='performance-history/v1',kind='approval',id='new',parent_epoch='root',case='linear',cohort='cpu1',selected={ratios={2,2,2}}}
assert(core.epoch({approve},'linear','cpu1')=='new')
local base=core.baseline({approve},'linear','cpu1','new',c.policy)
assert(base.count==1 and base.approved)
local second={schema=approve.schema,kind='approval',id='fork',parent_epoch='root',case='linear',cohort='cpu1'}
assert(not pcall(core.epoch,{approve,second},'linear','cpu1'),'approval forks silently won')
-- Every case declares how many cores it is measured on (1 for single-core,
-- more for multicore runs); there is no implicit default.
do
	local cores_cfg={schema='performance-project/v1',project='pilot',history_url='file:///tmp/history',identity={runtime='LuaJIT',build_mode='optimized',concurrency=1},cases={{name='linear',mode='cg',metric='operations',command={'echo'},sizes={10,20},bounds={1.8,2.2}}}}
	assert(not pcall(config.validate,cores_cfg),'case without cores accepted')
	for _,bad in ipairs({0,-1,1.5,'2'}) do cores_cfg.cases[1].cores=bad; assert(not pcall(config.validate,cores_cfg),'invalid cores accepted: '..tostring(bad)) end
	for _,good in ipairs({1,12}) do cores_cfg.cases[1].cores=good; assert(pcall(config.validate,cores_cfg),'valid cores rejected: '..good) end
end
print('PASS: configuration, precedence, argv, epoch and cores contracts')
