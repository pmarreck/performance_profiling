-- I/O adapter for test feedback latency: begin/span/finish verbs around the
-- pure latency core. Spans are appended to a per-job scratch file under
-- $TMPDIR; finish evaluates them and writes one immutable history record.
local uv=require('luv')
local started_ns=tonumber(uv.hrtime())
local json=require('json')
local config=require('config')
local latency=require('latency')
-- provenance (and the printable-binary map it loads) is needed only by
-- begin/finish; span stays light because it runs once per wrapped command.
local function provenance() return require('provenance') end
local M={}
local function utc()
	local sec,usec=uv.gettimeofday()
	return os.date('!%Y-%m-%dT%H:%M:%S',sec)..('.%03dZ'):format(math.floor(usec/1000))
end
local function now_ns() return tonumber(uv.hrtime()) end
local USAGE=[[usage: performance-profile latency begin|span|finish [options]
  begin  --job ID [--config PATH]          Start a job: timestamp and source identity
  span   --job ID --name NAME --kind KIND [--fresh true|false] [--cache hit|miss|partial|unknown]
         [--skip-exit CODE] [--status unknown | -- COMMAND...]
                                           Run COMMAND with stdio and exit status passed through;
                                           exit CODE (1-255, e.g. 77) records a skip: INCOMPLETE
  finish --job ID --correctness pass|fail|incomplete|error [--config PATH] [--history-url URL]
         [--suite NAME] [--profile NAME] [--concurrency N] [--notify-state PATH]
         [--tests-declared N] [--tests-executed N] [--tests-skipped N] [--tests-failed N]
Kinds: queue setup dependency nix_eval compile execute mixed deliver other.
Argv and environment are never recorded. Over budget warns (exit 0) unless the
project's latency.enforce is true. Exit 1 when correctness is not PASS.
]]
local function scratch_dir()
	local dir=(os.getenv('TMPDIR') or '/tmp')..'/performance-profile-latency'
	uv.fs_mkdir(dir,tonumber('700',8))
	local s=assert(uv.fs_lstat(dir)); assert(s.type=='directory','latency scratch must be a directory')
	return dir
end
local function job_path(job)
	assert(config.name(job),'unsafe job ID')
	return scratch_dir()..'/'..job..'.ndjson'
end
local function append(path,record,flags)
	local fd=assert(uv.fs_open(path,flags or 'a',tonumber('600',8)))
	local line=json.encode(record)..'\n'
	-- One write of one line, so parallel spans appending to a job do not interleave.
	local n=assert(uv.fs_write(fd,line,-1)); assert(uv.fs_close(fd)); assert(n==#line,'short scratch write')
end
local function load_config(options)
	local path=assert(uv.fs_realpath(options.config or 'profiling.json'))
	local f=assert(io.open(path,'rb')); local cfg=config.validate_latency(json.decode(f:read('*a'))); f:close()
	return cfg,path:match('^(.*)/[^/]+$')
end
local function open_store(cfg,root,options)
	local storage=require('store').open(config.history_url(cfg,options,{PERFORMANCE_HISTORY_URL=os.getenv('PERFORMANCE_HISTORY_URL')}),cfg.project)
	assert(storage.directory~=root and storage.directory:sub(1,#root+1)~=root..'/','history must be outside the measured project')
	return storage
end
local function parse(args,keys,flags)
	local options,command={},nil
	local i=1
	while i<=#args do
		local a=args[i]
		if a=='--' then command={}; for j=i+1,#args do command[#command+1]=args[j] end; break
		elseif flags[a] then options[flags[a]]=true
		elseif keys[a] then i=i+1; if args[i]==nil then return nil,'missing value for '..a end; options[keys[a]]=args[i]
		else return nil,'unknown argument '..a end
		i=i+1
	end
	return options,command
end

local function begin(options)
	if not options.job then return 2,'--job required' end
	local cfg,root=load_config(options)
	local path=job_path(options.job)
	local t0=now_ns()
	local identity,head=provenance().tree_identity(root)
	local t1=now_ns()
	append(path,{type='begin',project=cfg.project,root=root,begin_ns=t0,identity_end_ns=t1,begin_utc=utc(),source=identity,git_head=head},'wx')
	return 0
end

local function span(options,command)
	if not options.job or not options.name or not options.kind then return 2,'--job, --name and --kind required' end
	if not latency.kinds[options.kind] or options.kind=='instrumentation' then return 2,'invalid kind '..options.kind end
	if options.fresh and options.fresh~='true' and options.fresh~='false' then return 2,'--fresh must be true or false' end
	local skip_exit
	if options.skip_exit then
		skip_exit=tonumber(options.skip_exit)
		if not options.skip_exit:match('^%d+$') or skip_exit<1 or skip_exit>255 then return 2,'--skip-exit must be an exit code 1-255' end
	end
	local path=job_path(options.job)
	if not uv.fs_lstat(path) then return 1,'job '..options.job..' has no begin; run latency begin first' end
	local s={type='span',name=options.name,kind=options.kind,cache=options.cache,fresh=options.fresh and options.fresh=='true' or nil,skip_exit=skip_exit,wrapper_start_ns=started_ns}
	if options.status=='unknown' then
		if command then return 2,'an unknown span runs no command' end
		s.status='unknown'; s.wrapper_end_ns=now_ns(); append(path,s); return 0
	end
	if options.status then return 2,'only --status unknown is supported' end
	if not command or #command==0 then return 2,'COMMAND required after --' end
	local rc,signal
	local spawn_args={}; for i=2,#command do spawn_args[i-1]=command[i] end
	s.status='measured'; s.start_utc=utc(); s.start_ns=now_ns()
	-- Inherited stdio: output streams straight through and is never buffered here.
	local handle,err=uv.spawn(command[1],{args=spawn_args,stdio={0,1,2}},function(code,sig) rc,signal=code,sig end)
	if not handle then
		s.end_ns=now_ns(); s.spawn_error=tostring(err); s.exit_code=127
		io.stderr:write('performance-profile latency: cannot start '..command[1]..': '..tostring(err)..'\n')
	else
		uv.run(); handle:close(); uv.run()
		s.end_ns=now_ns(); s.exit_code=rc; s.signal=signal
	end
	s.wrapper_end_ns=now_ns()
	append(path,s)
	if s.spawn_error then return 127 end
	if signal and signal~=0 then return 128+signal end
	return rc
end

local function cohort(options)
	local cpus,u=uv.cpu_info(),uv.os_uname()
	local hardware={version='latency-cohort/v1',os=u.sysname,arch=u.machine,cpu=cpus[1] and cpus[1].model or 'unavailable',logical_cpus=#cpus,suite=options.suite,profile=options.profile,concurrency=options.concurrency}
	return require('process').sha256(json.encode(hardware)),hardware
end
local function count(v,flag)
	if v==nil then return nil end
	local n=tonumber(v); assert(n and n>=0 and n%1==0,flag..' must be a non-negative integer'); return n
end
local function exit_status(record,cfg)
	if record.correctness~='PASS' then return 1 end
	if cfg.latency.enforce and record.latency=='OVER_BUDGET' then return 1 end
	return 0
end
local function notice(record,decision,state)
	local lines={latency.summary(record,{project=record.project,suite=record.suite,reference=record.reference})}
	if decision=='detail' then for _,l in ipairs(latency.detail(record)) do lines[#lines+1]='  '..l end
	elseif decision=='reminder' then lines[#lines+1]=('  still over budget since %s (reminder %d)'):format(os.date('!%Y-%m-%dT%H:%M:%SZ',state.over_since),state.reminders) end
	io.stderr:write(table.concat(lines,'\n')..'\n')
end
local function decide(record,path)
	local default=(record.correctness~='PASS' or record.latency=='OVER_BUDGET') and 'detail' or 'brief'
	if not path then return default end
	local previous
	local f=io.open(path,'rb'); if f then previous=json.decode(f:read('*a')); f:close() end
	local decision,state=latency.notify(previous,record,os.time(),{reminder_s=3600,max_reminders=3,worsen_fraction=0.10})
	local tmp=path..'.pending-'..uv.getpid()
	f=assert(io.open(tmp,'wb')); assert(f:write(json.encode(state))); assert(f:close()); assert(os.rename(tmp,path))
	return decision,state
end

local function finish(options)
	if not options.job then return 2,'--job required' end
	local corr={pass=true,fail=true,incomplete=true,error=true}
	if options.correctness and not corr[options.correctness] then return 2,'invalid --correctness' end
	local cfg,root=load_config(options)
	local storage=open_store(cfg,root,options)
	local path=job_path(options.job)
	local f=io.open(path,'rb')
	if not f then
		-- A completed job reruns as a no-op that reports its stored record.
		for _,r in ipairs(storage:read_latency()) do
			if r.id==options.job then io.write(json.encode(r)..'\n'); notice(r,'brief'); return exit_status(r,cfg) end
		end
		return 1,'unknown job '..options.job..' (no begin and no stored record)'
	end
	if not options.correctness then f:close(); return 2,'--correctness required' end
	local finish_ns=now_ns()
	local b,spans=nil,{}
	for line in f:lines() do
		local e=json.decode(line)
		if e.type=='begin' then b=e else spans[#spans+1]=e end
	end
	f:close()
	assert(b and b.project==cfg.project,'job began under a different project')
	local after=provenance().tree_identity(root)
	local history=storage:read_latency()
	local phases={{name='begin',kind='instrumentation',status='measured',start_ns=b.begin_ns,end_ns=b.identity_end_ns}}
	for _,s in ipairs(spans) do
		local p={name=s.name,kind=s.kind,status=s.status,start_ns=s.start_ns,end_ns=s.end_ns,exit_code=s.exit_code,signal=s.signal,spawn_error=s.spawn_error,skip_exit=s.skip_exit,fresh=s.fresh,cache=s.cache,start_utc=s.start_utc}
		phases[#phases+1]=p
		-- Wrapper time around each child is instrumentation overhead, kept visible.
		if s.status=='measured' then
			phases[#phases+1]={name=s.name..' wrapper',kind='instrumentation',status='measured',start_ns=s.wrapper_start_ns,end_ns=s.start_ns}
			phases[#phases+1]={name=s.name..' wrapper',kind='instrumentation',status='measured',start_ns=s.end_ns,end_ns=s.wrapper_end_ns}
		end
	end
	local before_write=now_ns()
	phases[#phases+1]={name='finish',kind='instrumentation',status='measured',start_ns=finish_ns,end_ns=before_write}
	local tests={declared=count(options.tests_declared,'--tests-declared'),executed=count(options.tests_executed,'--tests-executed'),skipped=count(options.tests_skipped,'--tests-skipped'),failed=count(options.tests_failed,'--tests-failed')}
	local has_tests=next(tests)~=nil
	local policy={target_ns=cfg.latency.target_ms*1000000,budget_ns=cfg.latency.budget_ms*1000000}
	options.suite=options.suite or 'test'; options.profile=options.profile or 'unspecified'; options.concurrency=options.concurrency or 'unspecified'
	local cohort_id,hardware=cohort(options)
	local r=latency.evaluate({phases=phases,correctness=options.correctness,tests=has_tests and tests or nil,begin_ns=b.begin_ns,end_ns=before_write,source_changed=after~=b.source},policy)
	r.schema='performance-latency/v1'; r.kind='latency'; r.project=cfg.project; r.id=options.job
	r.suite=options.suite; r.profile=options.profile; r.concurrency=options.concurrency
	r.cohort=cohort_id; r.hardware=hardware; r.datetime_utc=b.begin_utc; r.finished_utc=utc()
	r.git_head=b.git_head; r.source=b.source; r.source_after=after; r.source_changed=after~=b.source
	r.tests=has_tests and tests or nil; r.correctness_reported=options.correctness; r.enforced=cfg.latency.enforce
	r.reference=r.comparable and latency.reference(history,cohort_id,options.suite) or nil
	r.phases=phases
	storage:write_latency(r)
	local written=now_ns()
	os.remove(path)
	local decision,state=decide(r,options.notify_state)
	local out={}; for k,v in pairs(r) do out[k]=v end; out.history_write_ns=written-before_write
	io.write(json.encode(out)..'\n')
	notice(r,decision,state)
	return exit_status(r,cfg)
end

function M.main(args)
	local verb=table.remove(args,1)
	if verb==nil or verb=='--help' or verb=='-h' then io.write(USAGE); return verb and 0 or 2 end
	local keys={['--job']='job',['--config']='config',['--history-url']='history_url',['--name']='name',['--kind']='kind',['--fresh']='fresh',['--cache']='cache',['--status']='status',['--skip-exit']='skip_exit',['--correctness']='correctness',['--suite']='suite',['--profile']='profile',['--concurrency']='concurrency',['--notify-state']='notify_state',['--tests-declared']='tests_declared',['--tests-executed']='tests_executed',['--tests-skipped']='tests_skipped',['--tests-failed']='tests_failed'}
	local options,command=parse(args,keys,{})
	if not options then io.stderr:write(command..'\n'); return 2 end
	local handlers={begin=begin,span=span,finish=finish}
	if not handlers[verb] then io.stderr:write('unknown latency verb '..verb..'\n'..USAGE); return 2 end
	local rc,message=handlers[verb](options,command)
	if message then io.stderr:write('performance-profile latency: '..message..'\n') end
	return rc
end
return M
