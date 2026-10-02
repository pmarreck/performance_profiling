local uv=require('luv')
local process=require('process')
local json=require('json')
local core=require('core')
local enc=require('encoding')
local cpuset=require('cpus')
local M={}
local function read(path)
	local f=assert(io.open(path,'rb')); local bytes=assert(f:read('*a')); assert(f:close()); return bytes
end
local function git(root,args)
	local argv={'git','-C',root}; for _,a in ipairs(args) do argv[#argv+1]=a end
	return process.checked(argv)
end
local function entries(data)
	local out={}; for s in data:gmatch('([^%z]+)%z') do out[#out+1]=s end; return out
end
local function resolve(program,root)
	if program:sub(1,1)=='/' then return program end
	if program:find('/',1,true) then return root..'/'..program end
	for dir in (os.getenv('PATH') or ''):gmatch('[^:]+') do
		local p=dir..'/'..program
		if uv.fs_stat(p) then return p end
	end
	error('executable not found: '..program)
end
M.resolve=resolve
function M.snapshot(root,cfg)
	local head=git(root,{'rev-parse','HEAD'}):gsub('%s+$','')
	local changes={}
	-- Disable rename collapsing: both old/new paths get unambiguous raw counts.
	for item in git(root,{'diff','HEAD','--numstat','-z','--no-renames'}):gmatch('([^%z]+)%z') do
		local added,deleted,path=item:match('^([^\t]+)\t([^\t]+)\t(.*)$')
		assert(path,'invalid Git numstat')
		if core.code_path(path) then changes[#changes+1]={path=enc.encode(path),added=tonumber(added) or json.decode('null'),deleted=tonumber(deleted) or json.decode('null'),status='tracked-dirty'} end
	end
	local tracked=entries(git(root,{'ls-files','-z'}))
	local untracked=entries(git(root,{'ls-files','--others','--exclude-standard','-z'}))
	for _,p in ipairs(untracked) do
		if core.code_path(p) then
			local bytes=read(root..'/'..p)
			local lines=not bytes:find('%z') and select(2,bytes:gsub('\n',''))+(#bytes>0 and bytes:sub(-1)~='\n' and 1 or 0) or json.decode('null')
			changes[#changes+1]={path=enc.encode(p),added=lines,deleted=0,status='untracked'}
		end
	end
	local paths,seen={},{ }
	for _,set in ipairs({tracked,untracked}) do
		for _,p in ipairs(set) do
			if not seen[p] then paths[#paths+1]=p; seen[p]=true end
		end
	end
	table.sort(paths)
	local contents,regular={},{'sha256sum','--zero','--'}
	for _,p in ipairs(paths) do
		local stat=uv.fs_lstat(root..'/'..p)
		local bytes='deleted'
		if stat then
			if stat.type=='file' then bytes='regular'; regular[#regular+1]=root..'/'..p
			elseif stat.type=='link' then bytes=assert(uv.fs_readlink(root..'/'..p))
			else bytes=stat.type end
		end
		contents[#contents+1]=#p..':'..p..#bytes..':'..bytes
	end
	-- Hash regular files in a streaming external adapter, without slurping fixtures.
	if #regular>3 then contents[#contents+1]=process.checked(regular) end
	local binaries={}
	for _,c in ipairs(cfg.cases) do
		local p=resolve(c.command[1],root)
		local digest=process.sha256(read(p)); binaries[#binaries+1]={path=enc.encode(p),sha256=digest}
	end
	local digest=process.sha256(table.concat(contents)..json.encode(binaries)..json.encode(cfg))
	return digest,{git={head=head,dirty_code=changes},binaries=binaries,cwd=enc.encode(root),encoding={name=enc.name,map_sha256=enc.map_sha256}}
end
function M.identity(cfg,case)
	local cpus=uv.cpu_info()
	local osname=uv.os_uname()
	local features='unavailable'
	if osname.sysname=='Linux' then
		local f=io.open('/proc/cpuinfo','rb')
		if f then local data=f:read('*a'); f:close(); features=data:match('\nflags%s*:%s*([^\n]+)') or data:match('\nFeatures%s*:%s*([^\n]+)') or features end
	end
	local hardware={version='cohort/v1',os=osname.sysname,arch=osname.machine,cpu=cpus[1] and cpus[1].model or 'unavailable',features=features,logical_cpus=#cpus,identity=cfg.identity,metric=case.metric,sizes=case.sizes,comparison=case.comparison or 'growth',case_definition=case.definition or case.name,measurement_method='mean-per-size/v1',cores=case.cores,affinity=cpuset.allowed() and 'taskset' or 'unenforced'}
	return process.sha256(json.encode(hardware)),hardware
end
function M.now()
	local sec,usec=uv.gettimeofday()
	return os.date('!%Y-%m-%dT%H:%M:%S',sec)..('.%03dZ'):format(math.floor(usec/1000))
end
function M.id() return assert(uv.random(16)):gsub('.',function(c) return ('%02x'):format(c:byte()) end) end
return M
