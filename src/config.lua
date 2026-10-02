local M={}
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
	end
	return cfg
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
