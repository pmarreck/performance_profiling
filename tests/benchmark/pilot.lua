-- Actual work and malloc/free requests, checked against independent arithmetic.
local uv=require('luv')
local entered=uv.hrtime()
local ffi=require('ffi')
local json=require('cjson')
ffi.cdef('void *malloc(size_t size); void free(void *ptr);')
local name,sizes,seed=arg[1],arg[2],arg[3]
assert(name and sizes and seed)
local rows,ready={},nil
for text in sizes:gmatch('[^,]+') do
	local n=assert(tonumber(text)); local samples={operations={},cpu_ns={},wall_ns={},peak_bytes={},allocation_count={},total_bytes={}}
	local residual={}
	for iteration=1,8 do
		local live,peak,allocations=0,0,0
		local function allocate(bytes)
			local p=ffi.C.malloc(bytes); assert(p~=nil); live=live+bytes; peak=math.max(peak,live); allocations=allocations+1; return ffi.cast('uint64_t*',p)
		end
		local function release(p,bytes) ffi.C.free(p); live=live-bytes end
		local data=allocate(n*8)
		for i=0,n-1 do data[i]=i+1 end
		if not ready and iteration==4 then ready=tonumber(uv.hrtime()-entered); io.write('performance-ready/v1\n'); io.stdout:flush() end
		local before_cpu,before_wall=os.clock(),uv.hrtime()
		local sum,operations=0,0
		for i=0,n-1 do sum=sum+tonumber(data[i]); operations=operations+1 end
		local wall=tonumber(uv.hrtime()-before_wall)
		local cpu=math.floor((os.clock()-before_cpu)*1e9+0.5)
		assert(sum==n*(n+1)/2,'independent result check failed')
		release(data,n*8)
		if iteration>3 then
			local j=iteration-3
			samples.operations[j]=operations; samples.cpu_ns[j]=cpu; samples.wall_ns[j]=wall
			samples.peak_bytes[j]=peak; samples.allocation_count[j]=allocations; samples.total_bytes[j]=n*8
			residual[j]=live
		end
	end
	rows[#rows+1]={size=n,samples=samples,residual_bytes=residual}
end
io.write(json.encode({schema='performance-measurement/v1',correct=true,build_mode='optimized',runtime=jit.version,seed=seed,
	startup={phase='adapter-enter-to-ready',wall_ns=ready,excludes='interpreter startup and initial luv load'},
	allocator_coverage='malloc requests for input vector only; Lua runtime excluded',rows=rows,
	cores_env=os.getenv('PERFORMANCE_CORES'),cpus_seen=(function() local f=io.open('/proc/self/status','rb') if not f then return nil end local s=f:read('*a') f:close() return s:match('Cpus_allowed_list:%s*([^\n]+)') end)()})..'\n')
