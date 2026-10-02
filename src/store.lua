local uv=require('luv')
local json=require('json')
local name=require('config').name
local M={}
local function path(url)
	assert(type(url)=='string','history URL required')
	local p=url:match('^file://(/.*)$') or url:match('^file://localhost(/.*)$')
	assert(p and not p:find('[?#]'),'only absolute local file:// URLs are supported')
	assert(not p:gsub('%%[%x][%x]',''):find('%%'),'invalid URL escape')
	p=p:gsub('%%([%x][%x])',function(h) return string.char(tonumber(h,16)) end)
	assert(not p:find('%z'),'NUL in history path')
	return p:gsub('/+$','')
end
M.path=path
local function read(p)
	local s=assert(uv.fs_lstat(p)); assert(s.type=='file','history record must be a regular file: '..p)
	local f=assert(io.open(p,'rb')); local data=assert(f:read('*a')); assert(f:close()); return data
end
local function filename(project,kind,id)
	assert(name(id),'unsafe record ID'); assert(kind=='observation' or kind=='approval','unknown record kind')
	return project..'--'..kind..'--'..id..'.ndjson'
end
function M.open(url,project)
	assert(name(project),'unsafe project name')
	local dir=path(url); local stat=assert(uv.fs_lstat(dir)); assert(stat.type=='directory','history directory must exist and be a directory')
	dir=assert(uv.fs_realpath(dir))
	local obj={directory=dir,project=project}
	function obj:read()
		local scan=assert(uv.fs_scandir(dir)); local records={}
		while true do
			local f=uv.fs_scandir_next(scan); if not f then break end
			if f:sub(1,#project+2)==project..'--' and f:sub(-7)=='.ndjson' then
				local data=read(dir..'/'..f)
				assert(data:sub(-1)=='\n' and not data:sub(1,-2):find('\n'),'record must contain exactly one NDJSON line')
				local r=json.decode(data)
				assert(r.schema=='performance-history/v1','unsupported history schema')
				assert(r.project==project and filename(project,r.kind,r.id)==f,'history identity mismatch')
				assert(type(r.datetime_utc)=='string','history timestamp required')
				records[#records+1]=r
			end
		end
		table.sort(records,function(a,b) if a.datetime_utc==b.datetime_utc then return a.id<b.id end; return a.datetime_utc<b.datetime_utc end)
		return records
	end
	function obj:write(r)
		assert(r.schema=='performance-history/v1' and r.project==project,'record project/schema mismatch')
		local final=dir..'/'..filename(project,r.kind,r.id)
		local data=json.encode(r)..'\n'
		if uv.fs_lstat(final) then assert(read(final)==data,'conflicting record ID'); return 'exists' end
		local suffix=assert(uv.random(16)):gsub('.',function(c) return ('%02x'):format(c:byte()) end)
		local tmp=dir..'/.pending-'..suffix
		local fd=assert(uv.fs_open(tmp,'wx',tonumber('660',8)))
		local ok,err=pcall(function()
			local offset=0
			while offset<#data do local n=assert(uv.fs_write(fd,data:sub(offset+1),offset)); assert(n>0,'short history write'); offset=offset+n end
			assert(uv.fs_fsync(fd))
		end)
		local closed,close_err=uv.fs_close(fd)
		if not ok or not closed then uv.fs_unlink(tmp); error(err or close_err) end
		local linked,link_err,code=uv.fs_link(tmp,final)
		local removed,remove_err=uv.fs_unlink(tmp)
		assert(removed,remove_err)
		if not linked then
			assert(code=='EEXIST',link_err)
			assert(read(final)==data,'conflicting concurrent record ID')
		end
		local directory_fd=assert(uv.fs_open(dir,'r',0))
		local synced,sync_err=uv.fs_fsync(directory_fd); assert(uv.fs_close(directory_fd)); assert(synced,sync_err)
		return linked and 'created' or 'exists'
	end
	return obj
end
return M
