local M={}
M.default_deadline_ms=30000
M.max_deadline_ms=3600000
local metrics={operations=true,cpu_ns=true,wall_ns=true,peak_bytes=true,allocation_count=true,total_bytes=true,startup_ns=true}
local function name(n) return type(n)=='string' and #n<=100 and not n:find('--',1,true) and n:match('^[A-Za-z0-9_%-]+$')~=nil end
M.name=name
local function number(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
function M.validate(cfg)
	local function copy(value)
		if type(value)~='table' then return value end
		local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
	end
	cfg=copy(cfg)
	assert(cfg.schema=='performance-project/v1','unsupported project schema')
	assert(name(cfg.project),'unsafe project name')
	assert(type(cfg.history_url)=='string','project history_url required')
	assert(type(cfg.identity)=='table' and type(cfg.identity.runtime)=='string' and type(cfg.identity.build_mode)=='string' and number(cfg.identity.concurrency) and cfg.identity.concurrency>=1 and cfg.identity.concurrency%1==0,'runtime/build/positive integer concurrency identity required')
	assert(type(cfg.cases)=='table' and #cfg.cases>0,'cases required')
	local seen={}
	for _,c in ipairs(cfg.cases) do
		assert(name(c.name) and not seen[c.name],'unsafe or duplicate case name'); seen[c.name]=true
		assert(c.mode=='cg' or c.mode=='mg' or c.mode=='bm','unknown case mode')
		assert(metrics[c.metric],'unknown metric')
		assert(c.comparison==nil or c.comparison=='growth' or c.comparison=='absolute','invalid comparison method')
		assert(type(c.sizes)=='table' and #c.sizes>=(c.comparison=='absolute' and 1 or 2),'size sweep required')
		for i,n in ipairs(c.sizes) do assert(number(n) and n>0 and n%1==0 and (c.comparison=='absolute' or i==1 or n==c.sizes[i-1]*2),'sizes must double') end
		assert(type(c.bounds)=='table' and #c.bounds==2 and number(c.bounds[1]) and number(c.bounds[2]) and c.bounds[2]>=c.bounds[1],'invalid declared bounds')
		assert(type(c.command)=='table' and #c.command>0,'argv command required')
		for _,a in ipairs(c.command) do assert(type(a)=='string' and not a:find('%z'),'invalid command argument') end
		assert(#c.command[1]>0,'empty executable')
		assert(c.ready_marker==nil or (type(c.ready_marker)=='string' and #c.ready_marker>0 and not c.ready_marker:find('[\r\n%z]')),'readiness marker must be one nonempty line')
		assert(c.metric~='startup_ns' or (c.comparison=='absolute' and #c.sizes==1 and c.ready_marker),'startup requires absolute comparison, one size and readiness marker')
		c.policy=c.policy or {}
		local defaults={percent=10,sigma=3,minimum=3,window=20,max_cv=0.3,absolute_floor=0}
		for k,d in pairs(defaults) do if c.policy[k]==nil then c.policy[k]=d end; assert(number(c.policy[k]),'invalid policy '..k) end
		assert(c.policy.minimum>=2 and c.policy.minimum%1==0 and c.policy.window>=c.policy.minimum and c.policy.window%1==0,'invalid history sample/window policy')
		assert(c.policy.max_cv>0,'noise tolerance must be positive')
		assert(c.residual_allowance==nil or number(c.residual_allowance),'invalid residual allowance')
		if c.processes==nil then c.processes=1 end
		assert(type(c.processes)=='number' and c.processes>=1 and c.processes%1==0 and c.processes%2==1,'processes must be an odd positive integer')
		assert(c.metric~='startup_ns' or c.processes==1,'startup cases already spawn five processes; processes must be 1')
		assert(type(c.cores)=='number' and c.cores>=1 and c.cores%1==0,'cores must be a positive integer: 1 for single-core, more for multicore')
		assert(c.timeout_ms==nil or (number(c.timeout_ms) and c.timeout_ms>=1 and c.timeout_ms<=M.max_deadline_ms and c.timeout_ms%1==0),'timeout_ms must be integer milliseconds in 1..'..M.max_deadline_ms)
	end
	return cfg
end
-- Per-process kill deadline for a case. The default is applied here rather
-- than written into the validated configuration, whose bytes feed the source
-- digest, so existing configurations keep their source identity.
function M.deadline_ms(case) return case.timeout_ms or M.default_deadline_ms end
-- Projects that only record test feedback latency need no cg/mg cases.
-- Budget policy defaults to a 1 s target and 5 s budget, unenforced.
function M.validate_latency(cfg)
	assert(type(cfg)=='table' and cfg.schema=='performance-project/v1','unsupported project schema')
	assert(name(cfg.project),'unsafe project name')
	assert(type(cfg.history_url)=='string','project history_url required')
	local l=cfg.latency or {}
	local out={target_ms=l.target_ms==nil and 1000 or l.target_ms,budget_ms=l.budget_ms==nil and 5000 or l.budget_ms,enforce=l.enforce}
	if out.enforce==nil then out.enforce=false end
	for _,k in ipairs({'target_ms','budget_ms'}) do assert(number(out[k]) and out[k]>=1 and out[k]%1==0,'latency '..k..' must be positive integer milliseconds') end
	assert(out.target_ms<=out.budget_ms,'latency target must not exceed budget')
	assert(type(out.enforce)=='boolean','latency enforce must be true or false')
	return {schema=cfg.schema,project=cfg.project,history_url=cfg.history_url,latency=out}
end
function M.history_url(cfg,options,env)
	return options.history_url or env.PERFORMANCE_HISTORY_URL or cfg.history_url
end
function M.command(case,seed)
	local variables={case=case.name,sizes=table.concat(case.sizes,','),seed=tostring(seed)}
	local argv={}
	for i,a in ipairs(case.command) do argv[i]=a:gsub('{([a-z]+)}',function(key) return assert(variables[key],'unknown argv placeholder '..key) end) end
	return argv
end
return M
