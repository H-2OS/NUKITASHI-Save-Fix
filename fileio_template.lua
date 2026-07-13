----------------------------------------
-- file入出力 [PATCHED]
-- - isSaveFile: saveg.dat消失時のDisk Fallback
-- - restore:    ロード時のメタデータ自動復旧
----------------------------------------
function store(e, p)
	message("通知", p.file, "をセーブしました")
	saveconv(true)
end
----------------------------------------
-- ■ ロード時に自動で呼ばれる
function restore(e, p)
	message("通知", p.file, "をロードしました")
	loadconv(true)
	-- metadata auto-recovery: restore title & text & date from loaded scr
	local function __recover_metadata()
		local no = tonumber(tostring(p.file):match("save(%d+)"))
		if no and no < init.save_suspend then
			local t = sys.saveslot[no]
			if t then
				local need_save = false
				local ti = sv.getsavetitle()
				if ti and next(ti) ~= nil then t.title = ti; need_save = true end
				if scr.ip and scr.ip.save then
					local tx = scr.ip.save.text
					local dt = scr.ip.save.date
					if tx and tx ~= "" then
						if type(tx) ~= "string" or tx ~= "autosave" then
							t.text = tx; need_save = true
						end
					end
					if dt and type(dt) == "table" and #dt >= 6 then
						t.date = dt; need_save = true
					end
				end
				if need_save then asyssave() end
			end
		end
	end
	pcall(__recover_metadata)
	loadstart = true
	e:tag{"var", name="s.status.controlskip", data="0"}
	local uinm = scr.uifunc
	if scr.menu and uinm ~= 'menu' then sv.delpoint() end
	if uinm then local v = openui_table[uinm]; if v then _G[v[2]]({}) end end
	appex = nil; extra = nil; titlepage = nil
	scr.menu = nil; scr.uifunc = nil; scr.adv.memory = nil; scr.bgmfade = nil
	adv_flagreset(); allkeyon(); autoskip_init()
	sv.delpoint(); init_adv_btn()
	if temp_dialog then set_dlgparam(temp_dialog, 1); temp_dialog = nil; asyssave() end
	readScriptFile(scr.ip.file)
	if suspend_load then
		local file = e:var("s.savepath").."/"..sv.makefile(init.save_suspend)..".dat"
		tag{"file", command="delete", target=(file)}
	elseif scr.autosave then
		if scr.select then flg.autosave = true end
		scr.autosave = nil
	elseif scr.loadfunc then
		flg.ui = {}; setonpush_ui(); estag("init"); estag{ scr.loadfunc[1] }
		estag{"uitrans"}; estag{"eqwait"}; estag("stop"); return
	end
	conf_reload(); anime_reload(); checkAread(); set_caption()
	loading_off(); uimask_on(); tag{"lydel", id="zzlogn"}
	quickjumpui(#(log.stack or {}), "load")
end
----------------------------------------
function load_suspendcheck()
	if suspend_load and get_dlgparam("sus") == 0 then suspend_load = nil; dialog("oksus") end
end
function load_suspendcheck2() ResetStack(); quickjumpmsgmain() end
----------------------------------------
function save_system() fsave_pluto(init.save_system, sys) end
function save_global() fsave_pluto(init.save_global, gscr) end
function save_config() fsave_pluto(init.save_config, conf) end
function load_system() sys = fload_pluto(init.save_system) or {} end
function load_global() gscr = fload_pluto(init.save_global) or {} end
function load_config() conf = fload_pluto(init.save_config) or {} end
----------------------------------------
function saveconv(flag)
	save_playtime(); save_system(); save_global(); save_config()
	if flag then fsave_pluto("scr", scr); fsave_pluto("log", log); fsave_pluto("btn", btn) end
end
function loadconv(flag)
	save_playtime(); load_system(); load_global(); load_config()
	if flag then scr = fload_pluto("scr"); log = fload_pluto("log"); btn = fload_pluto("btn") end
end
function tags.syssave(e, param) syssave() return 1 end
function syssave() message("通知", "system dataをセーブしました"); saveconv(); eqtag{"save"} end
function asyssave() if not game.cs then syssave() end end
function pssyssave() if game.cs then tag{"call", file="system/ui.asb", label="pssyssave"} else syssave() end end
function save_playtime() local t = gscr.playtime or 0; t = t + e:now() - playtime; gscr.playtime = t; playtime = e:now() end
----------------------------------------
function fload(file, flag)
	local path = ""; if not flag then path = e:var("s.savepath")..'/' end
	local r = e:file(path..file); if r then r = pluto.unpersist({}, r) end
	return r
end
function fsave(file, tbl, flag)
	local path = ""; if not flag then path = e:var("s.savepath")..'/' end
	local fp = io.open((path..file), "wb")
	if fp then fp:write(pluto.persist({}, tbl)); io.close(fp) end
	return fp
end
function fload_pluto(name)
	local r = nil; local p = e:var(name or "t.dummy")
	if p ~= "0" then r = pluto.unpersist({}, p) end
	return r
end
function fsave_pluto(name, tbl) e:tag{"var", name=(name), data=(pluto.persist({}, tbl))} end
function deleteFile(path) e:tag{"file", command="delete", target=(path)} end
function readtable(file, name)
	local tbl = { ui=(game.path.ui) }; local path = (name and tbl[name] or "")..file
	if e:isFileExists(path) then e:include(path) else error_message(path.."はみつかりませんでした") end
end
function isFile(path) return path and e:isFileExists(path) end
----------------------------------------
-- ■ isSaveFile関数
-- [PATCHED] saveg.datのsaveslot消失時、ディスク上の
-- saveNNNN.dat実ファイルを確認して自動復旧。日付は_save_dates表から。
function isSaveFile(num, name)
	local ret = nil
	local no = tonumber(num) or 1
	if name == "quick" then no = no + game.qsavehead
	elseif name == "auto"  then no = no + game.asavehead end

	local file = nil; local mask = nil
	local s = sys.saveslot[no]

	if s then
		file = s.file; ret = s; mask = s.evmask
	else
		-- FALLBACK: saveslot消失時、ディスク上の実ファイルを確認
		local fname = (init.save_prefix or "save") .. string.format("%04d", no)
		if isFile(e:var("s.savepath") .. '/' .. fname .. ".dat") then
			file = fname
			ret = {
				text  = "",
				title = {},
				date  = (_save_dates[no] or get_unixtime()),
				file  = fname,
				evmask= nil,
			}
			sys.saveslot[no] = ret
		end
	end

	if not game.cs and file then
		if init.game_savemode == "new" then
			if mask then
				local ss = ":hev/"..mask
				if not isFile(ss..".png") and not isFile(ss..".jpg") and not isFile(ss..".jpeg") then ret = nil end
			elseif not isFile(e:var("s.savepath")..'/'..file..".png") then
				ret = nil
			end
		elseif not isFile(e:var("s.savepath")..'/'..file..".dat") then
			ret = nil
		end
	end
	return ret
end
----------------------------------------
-- DATE_TABLE_PLACEHOLDER --
----------------------------------------
function open_savepath()
	if game.trueos == "windows" then
		se_ok(); local fl = "explorer"
		e:callShellExecute{ file=(fl), option=(code_sjis(e:var("s.savepath"))) }
	end
end
----------------------------------------
function opensli(path, num)
	local ret = {}; local frq = num or init.voice_freq
	if not path:find(".ogg") then path = path..".ogg.sli" end
	if isFile(path) then
		for i, line in pairs(split(e:file(path), "\n")) do
			if string.sub(line, 0, 5) == "Label" then
				local s = line:gsub("[ ']", ""):gsub("=", ";")
				local ax = split(s, ";")
				table.insert(ret, math.floor(tonumber(ax[2] or 0) / frq))
			end
		end
	else ret = nil end
	return ret
end
----------------------------------------
