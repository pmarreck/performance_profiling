local uv=require('luv')
local M={}
function M.run(argv,options)
	options=options or {}
	local out,err={},{}
	local stdin,stdout,stderr=uv.new_pipe(false),uv.new_pipe(false),uv.new_pipe(false)
	local args={}; for i=2,#argv do args[i-1]=argv[i] end
	local rc,signal,timed_out,handle
	local clock=options.clock or function() return tonumber(uv.hrtime()) end
	local started,ready_ns=clock(),nil
	local timer=uv.new_timer()
	handle=uv.spawn(argv[1],{args=args,cwd=options.cwd,stdio={stdin,stdout,stderr}},function(code,sig)
		rc,signal=code,sig; timer:stop(); timer:close(); handle:close()
	end)
	if not handle then
		stdin:close(); stdout:close(); stderr:close(); timer:close(); uv.run()
		return {rc=127,stdout='',stderr='cannot spawn '..argv[1]}
	end
	local function reader(pipe,chunks)
		uv.read_start(pipe,function(e,chunk)
			if e then chunks[#chunks+1]=tostring(e) end
			if chunk then
				chunks[#chunks+1]=chunk
				if pipe==stdout and options.ready_marker and not ready_ns and table.concat(chunks):sub(1,#options.ready_marker+1)==options.ready_marker..'\n' then ready_ns=clock()-started end
			else pipe:close() end
		end)
	end
	reader(stdout,out); reader(stderr,err)
	local function finish_input()
		uv.shutdown(stdin,function() stdin:close() end)
	end
	if options.stdin and #options.stdin>0 then uv.write(stdin,options.stdin,finish_input) else finish_input() end
	timer:start(options.timeout_ms or 30000,0,function() timed_out=true; handle:kill('sigkill') end)
	uv.run()
	return {rc=rc,signal=signal,stdout=table.concat(out),stderr=table.concat(err),timed_out=timed_out or false,ready_ns=ready_ns}
end
function M.checked(argv,options)
	local r=M.run(argv,options)
	assert(r.rc==0 and r.signal==0 and not r.timed_out,table.concat(argv,' ')..': '..r.stderr)
	return r.stdout
end
function M.sha256(bytes)
	return assert(M.checked({'sha256sum'},{stdin=bytes}):match('^([a-f0-9]+)'))
end
return M
