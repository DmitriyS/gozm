#include <amxmodx>
#include <amxmisc>
#include <biohazard>
#include <sqlx>
#include <hamsandwich>
#include <time>
#include <fakemeta>
#include <colored_print>

#pragma dynamic 16384

#define PLUGIN "[BIO] Statistics"
#define VERSION "0.1"
#define AUTHOR "Dimka"

//#define ZP_STATS_DEBUG
//#define QUERY_DEBUG
 
#define column(%1) SQL_FieldNameToNum(query, %1)

enum 
{
	KILLER_ID,
	KILLER_HP,
	KILLER_ARMOUR,
	KILLER_NUM
}

enum 
{
	ME_DMG,
	ME_HIT,
	ME_INFECT,
	ME_KILLS,
	ME_NUM
}

new g_StartTime[33]
new g_UserIP[33][32], g_UserAuthID[33][32], g_UserName[33][32]
new g_UserDBId[33], g_TotalDamage[33]
new bool:g_UserPutInServer[33]

new Handle:g_SQL_Connection, Handle:g_SQL_Tuple

new g_Query[3024]

new g_CvarAllowHp, g_CvarAllowMe
new g_CvarShowBest
new g_CvarHost, g_CvarUser, g_CvarPassword, g_CvarDB

new g_CvarAuthType, g_CvarExcludingNick

new g_damagedealt[33]

new const g_types[][]={"first_zombie", "infect", "zombiekills", "humankills", "nemkills", "survkills", "suicide"}
	
new g_Killers[33][KILLER_NUM]
new g_Me[33][ME_NUM]
//new g_Best[33]

new g_OldRank[33]

new g_text[5096]

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	g_CvarHost = register_cvar("zp_stats_host", "89.20.147.155")
	g_CvarDB = register_cvar("zp_stats_db", "b179761")
	g_CvarUser = register_cvar("zp_stats_user", "u179761")
	g_CvarPassword = register_cvar("zp_stats_password", "Iqalebeq")
	
	register_cvar("zp_web_stats_version", VERSION, FCVAR_SERVER|FCVAR_SPONLY)
	
	g_CvarAllowHp = register_cvar("zp_stats_allow_hp", "1")
	g_CvarAllowMe = register_cvar("zp_stats_allow_me", "1")
	
	g_CvarShowBest = register_cvar("zp_stats_show_best_players", "1")
	
	g_CvarAuthType = register_cvar("zp_stats_auth_type", "3")
		
	g_CvarExcludingNick = register_cvar("zp_stats_ignore_nick", "[unreg]")
	
	register_clcmd("say", "handleSay")
	register_clcmd("say_team", "handleSay")
	
	RegisterHam(Ham_Killed, "player", "fw_HamKilled")
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage", 1)
	RegisterHam(Ham_CS_RoundRespawn, "player", "fw_CS_RoundRespawn", 1)
	
	register_logevent("logevent_endRound", 2, "1=Round_End")
	
	register_dictionary("time.txt")
	register_dictionary("zp_web_stats.txt")
	
}

public plugin_cfg()
{
	
	new cfgdir[32]
	get_configsdir(cfgdir, charsmax(cfgdir))
	server_cmd("exec %s/zp_web_stats.cfg", cfgdir)
	
	new host[32], db[32], user[32], password[32]
	get_pcvar_string(g_CvarHost, host, 31)
	get_pcvar_string(g_CvarDB, db, 31)
	get_pcvar_string(g_CvarUser, user, 31)
	get_pcvar_string(g_CvarPassword, password, 31)
	
	g_SQL_Tuple = SQL_MakeDbTuple(host,user,password,db)
	
	new err, error[256]
	g_SQL_Connection = SQL_Connect(g_SQL_Tuple, err, error, charsmax(error))
	
	if(g_SQL_Connection != Empty_Handle)
	{
		log_amx("%L",LANG_SERVER, "CONNECT_SUCSESSFUL")
	}
	else
	{
		log_amx("%L",LANG_SERVER, "CONNECT_ERROR", err, error)
		pause("a")
	}
	
	SQL_QueryAndIgnore(g_SQL_Connection, "SET NAMES utf8;")
}

public plugin_end()
{
	SQL_FreeHandle(g_SQL_Tuple)
	SQL_FreeHandle(g_SQL_Connection)
}

public client_authorized(id)
{
	g_UserPutInServer[id] = false
	
	fw_CS_RoundRespawn(id)
	
	g_StartTime[id] = get_systime()
	
	g_UserDBId[id] = 0
	
	g_TotalDamage[id] = 0
				
	g_OldRank[id] = 0			
	
	new unquoted_name[32], exluding_nick[32]
	get_user_name(id,unquoted_name,31)
	
	get_pcvar_string(g_CvarExcludingNick, exluding_nick, 31)
	if (exluding_nick[0] && containi(unquoted_name, exluding_nick) != -1)
		return
	
	SQL_QuoteString(g_SQL_Connection , g_UserName[id], 31, unquoted_name)
					
	get_user_authid(id,g_UserAuthID[id],31)
		
	get_user_ip(id,g_UserIP[id],31,1)
	
	g_damagedealt[id] = 0
	
	new uniqid[32]
	new whereis[10]
	new condition[40]
	
	new auth_type = get_pcvar_num(g_CvarAuthType)
	if (auth_type == 1)
	{
		copy(whereis,9,"steam_id")
		copy(uniqid,31,g_UserAuthID[id])
	}
	else
	if (auth_type == 2)
	{
		copy(whereis,9,"ip")
		copy(uniqid,31,g_UserIP[id])
	}
	else
	if (auth_type == 3)
	{
		copy(whereis,9,"nick")
		copy(uniqid,31,g_UserName[id])
	}
	else
	{
		if (equal(g_UserAuthID[id],"STEAM_0:",8))
		{
			copy(whereis,9,"steam_id")
			copy(uniqid,31,g_UserAuthID[id])
		}
		else
		{
			copy(whereis,9,"ip")
			copy(uniqid,31,g_UserIP[id])
			copy(condition, 39, " AND NOT (`steam_id` LIKE 'STEAM_0:%')")
		}
	}
	
	format(g_Query,charsmax(g_Query),"SELECT `id` FROM `zp_players` \
			WHERE `%s`='%s' %s;", whereis, uniqid, condition)
	
	new data[2]
	data[0] = id
	data[1] = get_user_userid(id)
    
    #if defined QUERY_DEBUG
        new now = get_systime()
    #endif
	SQL_ThreadQuery(g_SQL_Tuple, "ClientAuthorized_QueryHandler", g_Query, data, 2)
    #if defined QUERY_DEBUG
        if(get_systime() - now > 0) {
            log_amx("[WEBSTATS] Request <authorize> took %d seconds", get_systime() - now)
        }
    #endif
	
#if defined ZP_STATS_DEBUG
	log_amx("[ZP] Stats Debug: client %d autorized (Name %s, IP %s, Steam ID %s)", id, g_UserName[id], g_UserIP[id], g_UserAuthID[id])
#endif

}

public client_putinserver(id)
{
	
#if defined ZP_STATS_DEBUG
	new name[32]
	get_user_name(id, name, 31)
	log_amx("[ZP] Stats Debug: client %s %d put in server (DB id %d)", name, id, g_UserDBId[id])
#endif
	
	g_UserPutInServer[id] = true
}

public ClientAuthorized_QueryHandler(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
	if(FailState != TQUERY_SUCCESS)
	{
		log_amx("[ZP] Stats error %d, %s", err, error)
		return
	}
	
	new id = data[0]
	
	if (data[1] != get_user_userid(id))
		return
	
	if(SQL_NumResults(query))
	{
		g_UserDBId[id] = SQL_ReadResult(query, column("id"))
	}
	else
	{
		format(g_Query,charsmax(g_Query),"INSERT INTO `zp_players` SET\
					`nick`='%s',\
					`ip`='%s', `steam_id`='%s';",
					g_UserName[id], g_UserIP[id], g_UserAuthID[id])

		new Handle:queryyy = SQL_PrepareQuery(g_SQL_Connection, g_Query)
		SQL_Execute(queryyy)
		g_UserDBId[id] = SQL_GetInsertId(queryyy)
		SQL_FreeHandle(queryyy)
	}
	
#if defined ZP_STATS_DEBUG
	new name[32]
	get_user_name(id, name, 31)
	log_amx("[ZP] Stats Debug: client %s %d Query Handler (DB id %d)", name, id, g_UserDBId[id])
#endif	
}

public client_disconnect(id)
{
	
    if (!g_UserDBId[id] || !g_UserPutInServer[id])	
        return
/*
	new unquoted_name[32], name[32]
	get_user_name(id,unquoted_name,31)
	SQL_QuoteString(g_SQL_Connection , name, 31, unquoted_name)
	
	setc(g_UserName[id], 31, 0)
	
	new max_len =  charsmax(g_Query)
		
	format(g_Query, max_len, "UPDATE `zp_players` SET \
		`nick`='%s' WHERE `id`=%d;", 
		name, g_UserDBId[id])

	SQL_QueryAndIgnore(g_SQL_Connection, g_Query)
*/
    g_UserDBId[id] = 0
    
    new i
    for (i = 0; i < ME_NUM; i++)
		g_Me[id][i] = 0
}

public event_infect(id, infector)
{
    #if defined QUERY_DEBUG
        new now = get_systime()
    #endif

	if (infector)
	{
		if (g_UserDBId[id])
		{
			format(g_Query, charsmax(g_Query), "UPDATE `zp_players` SET `infected` = `infected` + 1 WHERE `id`=%d;", g_UserDBId[id])
			SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
		}
		
		if (g_UserDBId[infector])
		{
			format(g_Query, charsmax(g_Query), "UPDATE `zp_players` SET `infect` = `infect` + 1 WHERE `id`=%d;", g_UserDBId[infector])
			SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
		
			g_Me[infector][ME_INFECT]++
		}
			
	}
	else if (g_UserDBId[id])
	{
		format(g_Query, charsmax(g_Query), "UPDATE `zp_players` SET `first_zombie` = `first_zombie` + 1 WHERE `id`=%d;", g_UserDBId[id])
		SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
	}
    
    #if defined QUERY_DEBUG
        if(get_systime() - now > 0) {
            log_amx("[WEBSTATS] Request <event_infect> took %d seconds", get_systime() - now)
        }
    #endif
}

public logevent_endRound()
{
	if (get_playersnum())
	{
		if (get_pcvar_num(g_CvarShowBest))
		{
			new players[32], playersNum, i, maxInfectId = 0, maxDmgId = 0, maxKillsId = 0
			new maxInfectName[32], maxDmgName[32], maxKillsName[32]
			new extraMaxInfectNum = 0, maxInfectList[32]
			get_players(players, playersNum, "ch")
			for (i = 0; i < playersNum; i++)
			{
				if (g_Me[players[i]][ME_INFECT] > g_Me[players[maxInfectId]][ME_INFECT]) {
					maxInfectId = i
					extraMaxInfectNum = 0
					maxInfectList[extraMaxInfectNum] = i
				}
				else if (g_Me[players[i]][ME_INFECT] == g_Me[players[maxInfectId]][ME_INFECT] && (i != 0)) {
					extraMaxInfectNum++
					maxInfectList[extraMaxInfectNum] = i
				}
				if (g_Me[players[i]][ME_DMG] > g_Me[players[maxDmgId]][ME_DMG]) {
					maxDmgId = i
				}
				if (g_Me[players[i]][ME_KILLS] > g_Me[players[maxKillsId]][ME_KILLS])
					maxKillsId = i	
			}
			
			maxInfectId = maxInfectList[random_num(0, extraMaxInfectNum)]
			get_user_name(players[maxInfectId], maxInfectName, 31)
			get_user_name(players[maxDmgId], maxDmgName, 31)
			get_user_name(players[maxKillsId], maxKillsName, 31)
			
			if (g_Me[players[maxInfectId]][ME_INFECT] || 
				g_Me[players[maxKillsId]][ME_KILLS] ||
				g_Me[players[maxDmgId]][ME_DMG])
			{
				for (i = 0; i < playersNum; i++)
				{
					colored_print(players[i], "^x04======================================")
					colored_print(players[i], "^x04***^x01 Best Human:^x04 %s^x01  ->  [^x03  %d^x01 dmg  ]",
						maxDmgName, g_Me[players[maxDmgId]][ME_DMG])
					if (g_Me[players[maxInfectId]][ME_INFECT])
						colored_print(players[i], "^x04***^x01 Best Zombie:^x04 %s^x01  ->  [^x03  %d^x01 infection%s  ]",
							maxInfectName, g_Me[players[maxInfectId]][ME_INFECT], 
							(g_Me[players[maxInfectId]][ME_INFECT] > 1) ? "s" : "")
				}
			}
		}
	}
}

public fw_HamKilled(id, attacker, shouldgib)
{
    #if defined QUERY_DEBUG
        new now = get_systime()
    #endif

	if (is_user_alive(attacker) && g_UserDBId[attacker])
	{
		if (is_user_connected(attacker))
		{
			g_Killers[id][KILLER_ID] = attacker
			g_Killers[id][KILLER_HP] = get_user_health(attacker)
			g_Killers[id][KILLER_ARMOUR] = get_user_armor(attacker)
			g_Me[attacker][ME_KILLS] ++
		}
	}
	
	new type, player = attacker
	
	if (g_UserDBId[id] && is_user_connected(attacker))
	{
		format(g_Query, charsmax(g_Query), "UPDATE `zp_players` SET `death` = `death` + 1 WHERE `id`=%d;", g_UserDBId[id])
		SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
	}
	
	if (id == attacker || !is_user_connected(attacker))
	{
		type = 6
		player = id
	}
	else
	if (is_user_zombie(attacker))
	{
		type = 1
	}
	else
	{
		if (g_UserDBId[id])
		{
			type = 2
		}
	}
	
	if (g_UserDBId[player])
	{
		format(g_Query, charsmax(g_Query), "UPDATE `zp_players` SET `%s` = `%s` + 1 WHERE `id`=%d;", g_types[type], g_types[type], g_UserDBId[player])
		SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
	}
    
    #if defined QUERY_DEBUG
        if(get_systime() - now > 0) {
            log_amx("[WEBSTATS] Request <fw_HamKilled> took %d seconds", get_systime() - now)
        }
    #endif
}

public fw_TakeDamage(victim, inflictor, attacker, Float:damage, damage_type)
{
	if (victim == attacker || !is_user_alive(attacker) || !is_user_connected(victim) || !is_user_zombie(victim))
		return	
	
	if (is_user_alive(attacker) && g_UserDBId[attacker] && !is_user_zombie(attacker))
	{
		g_TotalDamage[attacker] += floatround(damage)
		g_Me[attacker][ME_DMG] += floatround(damage)
	}
}

public fw_CS_RoundRespawn(id)
{
	new i
	for (i = 0; i < KILLER_NUM; i++)
		g_Killers[id][i] = 0
	for (i = 0; i < ME_NUM; i++)
		g_Me[id][i] = 0
}

public handleSay(id)
{
	new args[64]
	
	read_args(args, charsmax(args))
	remove_quotes(args)
	
	new arg1[16]
	new arg2[32]
	
	strbreak(args, arg1, charsmax(arg1), arg2, charsmax(arg2))
	if (get_pcvar_num(g_CvarAllowHp) && equal(arg1,"/hp"))
		show_hp(id)
	else
	if (get_pcvar_num(g_CvarAllowMe) && equal(arg1,"/me"))
		show_me(id)	
	else
	if (equal(arg1,"/rank"))
		show_rank(id,arg2)
	else
	if (equal(arg1, "/rankstats") || equal(arg1, "/stats"))
		show_stats(id, arg2)
	else
	if (equal(arg1,"/top", 4))
	{
		if (arg1[4])
			show_top(id, str_to_num(arg1[4]))
		else
			show_top(id, 15)
	}
}

public show_hp(id)
{
	if (g_Killers[id][KILLER_ID])
	{
		new name[32]
		get_user_name(g_Killers[id][KILLER_ID], name, 31)
		colored_print(id, "^x04 ***^x01 Killed by^x04 %s^x01 (%d hp)",
			name, g_Killers[id][KILLER_HP])
	}
	else
		colored_print(id, "^x04 ***^x01 You have no killer.")
}

public show_me(id)
{
    if (g_Me[id][ME_DMG] && !is_user_zombie(id))
    {
        colored_print(id, "^x04***^x01 Last result:^x04 %d^x01 damage", g_Me[id][ME_DMG])
    }
    else if (g_Me[id][ME_INFECT] && is_user_zombie(id))
    {
        colored_print(id, "^x04***^x01 Last result:^x04 %d^x01 infection%s", 
            g_Me[id][ME_INFECT], g_Me[id][ME_INFECT] > 1 ? "s" : "")
    }
    else
        colored_print(id, "^x04 ***^x01 You have no hits")
}

public show_rank(id, unquoted_whois[])
{
	
	new whois[1024]
	SQL_QuoteString(g_SQL_Connection , whois, 1023, unquoted_whois)
	
	new rank
	new name[32]
	
	format(g_Query, charsmax(g_Query), "SET @_c = 0;")
	SQL_QueryAndIgnore(g_SQL_Connection, g_Query)
	
	new Handle:query
	
	if (!whois[0])
	{
		format(g_Query, charsmax(g_Query), "SELECT *,(SELECT COUNT(*) FROM `zp_players`) AS `total` FROM \
			(SELECT *, (@_c := @_c + 1) AS `rank`, \
			((`infect` + `zombiekills` + `humankills`) / (`infected` + `death` + 100)) AS `skill` ")
		query = SQL_PrepareQuery(g_SQL_Connection, "%s FROM `zp_players` \
			ORDER BY `skill` DESC) AS `newtable` WHERE `id`='%d';", 
			g_Query, g_UserDBId[id])
		
	}
	else
	{
		format(g_Query, charsmax(g_Query), "SELECT *,(SELECT COUNT(*) FROM `zp_players`) AS `total` FROM \
			(SELECT *, (@_c := @_c + 1) AS `rank`, \
			((`infect` + `zombiekills` + `humankills`) / (`infected` + `death` + 100)) AS `skill` ")
		query = SQL_PrepareQuery(g_SQL_Connection, "%s FROM `zp_players` ORDER BY `skill` DESC) AS `newtable` \
			WHERE `nick` LIKE '%%%s%%' OR `ip` LIKE '%%%s%%' \
			LIMIT 1;", 
			g_Query, whois, whois)
	}
	
	SQL_Execute(query)
	
	if (SQL_MoreResults(query))
	{
		SQL_ReadResult(query, column("nick"), name, 31)
		rank = SQL_ReadResult(query, column("rank"))
			
		colored_print(id, "^x04***^x03 %s^x01 is on^x04 %d^x01 place!",  name, rank)
	} 
	else
		colored_print(id, "^x04***^x03 %s^x01 should KILL MORE!", whois)
			
	SQL_FreeHandle(query)
}

public show_stats(id, unquoted_whois[])
{
	
	new infect, zombiekills
	new death, infected, rank, total, Float:skill, first_zombie
	
	
	new whois[1024]
	SQL_QuoteString(g_SQL_Connection , whois, 1023, unquoted_whois)
	
	new name[32], ip[32], steam_id[32]
	
	new len
			
	format(g_Query, charsmax(g_Query), "SET @_c = 0")
	SQL_QueryAndIgnore(g_SQL_Connection, g_Query)
	
	new Handle:query	
	if (!whois[0])
	{
		format(g_Query, charsmax(g_Query), "SELECT *,(SELECT COUNT(*) FROM `zp_players`) AS `total` FROM \
			(SELECT *, (@_c := @_c + 1) AS `rank`, \
			((`infect` + `zombiekills` + `humankills`) / (`infected` + `death` + 100)) AS `skill` ")
		query = SQL_PrepareQuery(g_SQL_Connection, "%s FROM `zp_players` \
			ORDER BY `skill` DESC) AS `newtable` WHERE `id`='%d';", 
			g_Query, g_UserDBId[id])
	}
	else
	{
		format(g_Query, charsmax(g_Query), "SELECT *,(SELECT COUNT(*) FROM `zp_players`) AS `total` FROM \
			(SELECT *, (@_c := @_c + 1) AS `rank`, \
			((`infect` + `zombiekills` + `humankills`) / (`infected` + `death` + 100)) AS `skill` ")
		query = SQL_PrepareQuery(g_SQL_Connection, "%s FROM `zp_players` ORDER BY `skill` DESC) AS `newtable` \
			WHERE `nick` LIKE '%%%s%%' OR `ip` LIKE '%%%s%%' \
			LIMIT 1;", 
			g_Query, whois, whois)
	}
	SQL_Execute(query)
	
	if (SQL_MoreResults(query))
	{
		SQL_ReadResult(query, column("nick"), name, 31)
		SQL_ReadResult(query, column("ip"), ip, 31)
		SQL_ReadResult(query, column("steam_id"), steam_id, 31)
		first_zombie = SQL_ReadResult(query, column("first_zombie"))
		infect = SQL_ReadResult(query, column("infect"))
		zombiekills = SQL_ReadResult(query, column("zombiekills"))
		death = SQL_ReadResult(query, column("death"))
		infected = SQL_ReadResult(query, column("infected"))
		rank = SQL_ReadResult(query, column("rank"))
		SQL_ReadResult(query, column("skill"), skill)		
		total = SQL_ReadResult(query, column("total"))
		
		replace_all(name, 32, ">", "gt;")
		replace_all(name, 32, "<", "lt;")
		
		new lStats[32]
		format(lStats, 31, "%L", id, "STATS")
		new lRank[32]
		format(lRank, 31, "%L", id, "RANK_STATS")
		new lInfect[32]
		format(lInfect, 31, "%L", id, "INFECT_STATS")
		new lZKills[32]
		format(lZKills, 31, "%L", id, "ZKILLS_STATS")
		new lHKills[32]
		format(lHKills, 31, "%L", id, "HKILLS_STATS")
		new lDeath[32]
		format(lDeath, 31, "%L", id, "DEATH")
		new lInfected[32]
		format(lInfected, 31, "%L", id, "INFECTED")
		new lFirstZombie[32]
		format(lFirstZombie, 31, "%L", id, "FIRST_ZOMBIE")
			
		new max_len = charsmax(g_text)
		len = format(g_text, max_len, "<html><head><meta http-equiv=^"Content-Type^" content=^"text/html; charset=utf-8^" /></head><body bgcolor=#000000>")
		len += format(g_text[len], max_len - len, "%s %s:<table style=^"color: #FFB000^"><tr><td>%s</td><td>%d/%d</td></tr><tr><td>%s</td><td>%d</td>",
			lStats, name, lRank, rank, total, lInfect, infect)
		len += format(g_text[len], max_len - len, "<tr><td>%s</td><td>%d</td></tr>",
			lZKills, zombiekills)
		len += format(g_text[len], max_len - len, "<tr><td>%s</td><td>%d</td></tr><tr><td>%s</td><td>%d</td></tr>",
			lDeath, death, lInfected, infected)
		len += format(g_text[len], max_len - len, "<tr><td>%s</td><td>%d</td></tr>",
			lFirstZombie, first_zombie)
		
		len += format(g_text[len], max_len - len, "<tr><td>%s</td><td>%s</td></tr><tr><td>%s</td><td>%s</td></tr>",
			"IP", ip, "Steam ID", steam_id)
		
		len += format(g_text[len], max_len - len, "</table></body></html>")
			
		show_motd(id, g_text, "Stats")
		
		setc(g_text, max_len, 0)
	} 
	else
		client_print(id, print_chat, "%L", id, "NOT_RANKED", whois)
			
	SQL_FreeHandle(query)
}

public show_top(id, top)
{
    new count, Handle:query
    new len
	
    new zombiekills, humankills, infect, name[32], rank, infected, death
    new Float:res
	
    new max_len = charsmax(g_text)
    		
    query = SQL_PrepareQuery(g_SQL_Connection, "SELECT COUNT(*) FROM `zp_players`;")
    SQL_Execute(query)
    if(SQL_MoreResults(query))
        count = SQL_ReadResult(query, 0)
    else
    {
        client_print(id, print_chat, "%L", id, "STATS_NULL")
        return
    }
	
    new lTop[32]
    format(lTop, 31, "%L", id, "TOP")
	
    new lLooserTop[32]
    format(lLooserTop, 31, "%L", id, "TOP_LOOSERS")
	
    new title[32]
    if (top <= 15)
        format(title, 31, "%s %d", lTop, top)
    else
    if (top < count)
        format(title, 31, "%s %d - %d", lTop, top - 14, top)
    else
    {
        top = count
        format(title, 31, "%s", lLooserTop)
    }
	
    setc(g_text, max_len, 0)
	
    format(g_Query, charsmax(g_Query), "SET @_c = 0")
    SQL_QueryAndIgnore(g_SQL_Connection, g_Query)
	
    query = SQL_PrepareQuery(g_SQL_Connection, "SELECT `nick`, `zombiekills`, `humankills`, \
            `infect`, `death`, `infected`, `rank` FROM \
            (SELECT *, (@_c := @_c + 1) AS `rank`, \
            ((`infect` + `zombiekills` + `humankills`) / (`infected` + `death` + 100)) AS `skill` \
            FROM `zp_players` \
            ORDER BY `skill` DESC) AS `newtable` WHERE `rank` <= %d ORDER BY `rank` DESC LIMIT 15;", 
            top)
			
    SQL_Execute(query)
	
    while (SQL_MoreResults(query))
    {
        SQL_ReadResult(query, column("nick"), name, 31)
        zombiekills = SQL_ReadResult(query, column("zombiekills"))
        humankills = SQL_ReadResult(query, column("humankills"))
        infect = SQL_ReadResult(query, column("infect"))
        infected = SQL_ReadResult(query, column("infected"))
        death = SQL_ReadResult(query, column("death"))
        rank = SQL_ReadResult(query, column("rank"))
        res = float(zombiekills + humankills + infect) / float(death + infected + 100)
        
        format(g_text, max_len, "<tr><td>%d<td>%s<td>%d<td>%d<td>%d<td>%d<td>%0.2f<td>%s",
            rank, name, zombiekills, infect, death, infected, res, g_text)
		
        SQL_NextRow(query)
    }
	
    SQL_FreeHandle(query)
	
    new lInfect[32]
    format(lInfect, 31, "%L", id, "INFECT_STATS")
    new lZKills[32]
    format(lZKills, 31, "%L", id, "ZKILLS_STATS")
    new lHKills[32]
    format(lHKills, 31, "%L", id, "HKILLS_STATS")
    new lDeaths[32]
    format(lDeaths, 31, "%L", id, "DEATH")
    new lInfected[32]
    format(lInfected, 31, "%L", id, "INFECTED")
    new result[32]
    format(result, 31, "%L", id, "RESULT")
    new lNick[32]
    format(lNick, 31, "%L", id, "NICK")
	
    len = format(g_text, max_len, "<html><head><meta http-equiv=^"Content-Type^" content=^"text/html; charset=utf-8^" /></head><body bgcolor=#000000><table style=^"color: #FFB000^"><tr><td>%s<td>%s<td>%s  <td>%s  <td>%s  <td>%s  <td>%s     <td>%s","#", lNick, lZKills, lInfect, lDeaths, lInfected, result, g_text)
    format(g_text[len], max_len - len, "</table></body></html>")	
	
    show_motd(id, g_text, title)
	
    setc(g_text, max_len, 0)
}

public threadQueryHandler(FailState, Handle:Query, error[], err, data[], size, Float:querytime)
{
	if(FailState != TQUERY_SUCCESS)
	{
		log_amx("[ZP] Stats: sql error: %d (%s)", err, error)
		return
	}
		
}

