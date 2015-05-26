#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <biohazard>
#include <sqlx>
#include <colored_print>
#include <gozm>

#define DEFAULT_TOP_COUNT       15
#define MAX_BUFFER_LENGTH       2047

#define STATSX_SHELL_DESIGN3_STYLE  "<meta charset=UTF-8><style>body{background:#E6E6E6;font-family:Verdana}th{background:#F5F5F5;color:#A70000;padding:6px;text-align:left}td{padding:2px 6px}table{color:#333;background:#E6E6E6;font-size:10px;font-family:Georgia;border:2px solid #D9D9D9}h2,h3{color:#333;}#c{background:#FFF}img{height:10px;background:#14CC00;margin:0 3px}#r{height:10px;background:#CC8A00}#clr{background:none;color:#A70000;font-size:20px;border:0}</style>"
#define STATSX_SHELL_DESIGN7_STYLE  "<meta charset=UTF-8><style>body{background:#FFF;font-family:Verdana}th{background:#2E2E2E;color:#FFF;text-align:left}table{padding:6px 2px;background:#FFF;font-size:11px;color:#333;border:1px solid #CCC}h2,h3{color:#333}#c{background:#F0F0F0}img{height:7px;background:#444;margin:0 3px}#r{height:7px;background:#999}#clr{background:none;color:#2E2E2E;font-size:20px;border:0}</style>"
#define STATSX_SHELL_DESIGN8_STYLE  "<meta charset=UTF-8><style>body{background:#242424;margin:20px;font-family:Tahoma}th{background:#2F3034;color:#BDB670;text-align:left} table{padding:4px;background:#4A4945;font-size:10px;color:#FFF}h2,h3{color:#D2D1CF}#c{background:#3B3C37}img{height:12px;background:#99CC00;margin:0 3px}#r{height:12px;background:#999900}#clr{background:none;color:#FFF;font-size:20px}</style>"
#define STATSX_SHELL_DESIGN10_STYLE "<meta charset=UTF-8><style>body{background:#4C5844;font-family:Tahoma}th{background:#1E1E1E;color:#C0C0C0;padding:2px;text-align:left;}td{padding:2px 10px}table{color:#AAC0AA;background:#424242;font-size:13px}h2,h3{color:#C2C2C2;font-family:Tahoma}#c{background:#323232}img{height:3px;background:#B4DA45;margin:0 3px}#r{height:3px;background:#6F9FC8}#clr{background:none;color:#FFF;font-size:20px}</style>"

#define PDATA_SAFE              2
#define OFFSET_DEATH            444

#define TASKID_AUTHORIZE        670
#define TASKID_LASTSEEN         671

#define column(%1)              SQL_FieldNameToNum(query, %1)

enum
{
    ME_DMG,
    ME_INFECT,
    ME_NUM
}

new g_UserIP[MAX_PLAYERS][32]
new g_UserAuthID[MAX_PLAYERS][32]
new g_UserName[MAX_PLAYERS][32]
new g_UserDBId[MAX_PLAYERS]

new Handle:g_SQL_Tuple

new g_Query[1024]
new whois[1024]

new g_CvarHost, g_CvarUser, g_CvarPassword, g_CvarDB
new g_CvarMaxInactiveDays

new g_Me[MAX_PLAYERS][ME_NUM]
new g_text[MAX_BUFFER_LENGTH + 1]
new bool:gb_css_trigger = true

new g_maxplayers

new g_isconnected[MAX_PLAYERS + 1]
new g_isalive[MAX_PLAYERS + 1]
#define is_user_valid_connected(%1) (1 <= %1 <= g_maxplayers && g_isconnected[%1])
#define is_user_valid_alive(%1) (1 <= %1 <= g_maxplayers && g_isalive[%1])

new const g_select_statement[] = "\
    (SELECT *, (@_c := @_c + 1) AS `rank`, \
    ((`infect` + `zombiekills`*2 + `humankills` + \
    `knife_kills`*5 + `best_zombie` + `best_human` + `best_player`*10) / \
    (`infected` + `death` + 300)) AS `skill` \
    FROM (SELECT @_c := 0) r, `bio_players` ORDER BY `skill` DESC) AS `newtable`"

public plugin_init()
{
    register_plugin("[BIO] Statistics", "1.3", "GoZm")

    if(!is_server_licenced())
        return PLUGIN_CONTINUE

    g_CvarHost = register_cvar("bio_stats_host", "195.128.158.196")
    g_CvarDB = register_cvar("bio_stats_db", "b179761")
    g_CvarUser = register_cvar("bio_stats_user", "u179761")
    g_CvarPassword = register_cvar("bio_stats_password", "petyx")
    g_CvarMaxInactiveDays = register_cvar("bio_stats_max_inactive_days", "30")

    register_clcmd("say", "handleSay")
    register_clcmd("say_team", "handleSay")

    RegisterHam(Ham_Killed, "player", "fw_HamKilled")
    RegisterHam(Ham_Spawn, "player", "fw_SpawnPlayer", 1)
    RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage", 1)

    register_event("HLTV", "event_newround", "a", "1=0", "2=0")

    register_logevent("logevent_endRound", 2, "1=Round_End")

    g_maxplayers = get_maxplayers()

    return PLUGIN_CONTINUE
}

public plugin_cfg()
{
    new cfgdir[32]
    get_configsdir(cfgdir, charsmax(cfgdir))
    server_cmd("exec %s/bio_stats.cfg", cfgdir)

    set_task(0.1, "sql_init")
}

public sql_init()
{
    if(!is_server_licenced())
        return

    new host[32], db[32], user[32], password[32]
    get_pcvar_string(g_CvarHost, host, charsmax(host))
    get_pcvar_string(g_CvarDB, db, charsmax(db))
    get_pcvar_string(g_CvarUser, user, charsmax(user))
    get_pcvar_string(g_CvarPassword, password, charsmax(password))

    g_SQL_Tuple = SQL_MakeDbTuple(host, user, password, db)

    if(!SQL_SetCharset(g_SQL_Tuple, "utf8"))
    {
        format(g_Query, charsmax(g_Query), "SET NAMES utf8")
        SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
    }

    new map_name[32]
    get_mapname(map_name, charsmax(map_name))
    format(g_Query, charsmax(g_Query), "\
        INSERT INTO `bio_maps` (`map`) \
        VALUES ('%s') \
        ON DUPLICATE KEY UPDATE `games` = `games` + 1", map_name)
    SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)

    new max_inactive_days = get_pcvar_num(g_CvarMaxInactiveDays)
    new inactive_period = get_systime() - max_inactive_days*24*60*60
    format(g_Query, charsmax(g_Query), "\
        DELETE FROM `bio_players` \
        WHERE `last_seen` < %d", inactive_period)
    SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
}

public plugin_end()
{
    SQL_FreeHandle(g_SQL_Tuple)
}

public client_putinserver(id)
{
    g_UserDBId[id] = 0
    g_isconnected[id] = true

    reset_player_statistic(id)
    set_task(0.1, "auth_player", TASKID_AUTHORIZE + id)
}

public client_disconnect(id)
{
    g_UserDBId[id] = 0
    g_isconnected[id] = false
    g_isalive[id] = false

    reset_player_statistic(id)
    remove_task(TASKID_AUTHORIZE + id)
    remove_task(TASKID_LASTSEEN + id)
}

public auth_player(taskid)
{
    new id = taskid - TASKID_AUTHORIZE
    if (!is_user_valid_connected(id) || !id || id > g_maxplayers)
        return PLUGIN_HANDLED

    new unquoted_name[64]
    get_user_name(id, unquoted_name, charsmax(unquoted_name))
    mysql_escape_string(unquoted_name, charsmax(unquoted_name))
    copy(g_UserName[id], charsmax(unquoted_name), unquoted_name)
    get_user_authid(id, g_UserAuthID[id], 31)
    get_user_ip(id, g_UserIP[id], 31, 1)

    format(g_Query, charsmax(g_Query), "\
        SELECT `id` FROM `bio_players` \
        WHERE BINARY `nick`='%s'", g_UserName[id])

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_SQL_Tuple, "ClientAuth_QueryHandler_Part1", g_Query, data, 2)

    return PLUGIN_HANDLED
}

public ClientAuth_QueryHandler_Part1(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
    if(FailState)
    {
        new szQuery[1024]
        SQL_GetQueryString(query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 1)
        return PLUGIN_HANDLED
    }

    new id = data[0]

    if (data[1] != get_user_userid(id))
        return PLUGIN_HANDLED

    if(SQL_NumResults(query))
    {
        g_UserDBId[id] = SQL_ReadResult(query, column("id"))
        set_task(10.0, "update_last_seen", TASKID_LASTSEEN + id)
    }
    else
    {
        format(g_Query,charsmax(g_Query), "\
            INSERT INTO `bio_players` \
            SET `nick`='%s', `ip`='%s', `steam_id`='%s'",
            g_UserName[id], g_UserIP[id], g_UserAuthID[id])
        SQL_ThreadQuery(g_SQL_Tuple, "ClientAuth_QueryHandler_Part2", g_Query, data, 2)
    }
    return PLUGIN_HANDLED
}

public ClientAuth_QueryHandler_Part2(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
    if(FailState)
    {
        new szQuery[1024]
        SQL_GetQueryString(query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 2)

        return PLUGIN_HANDLED
    }

    new id = data[0]
    if (data[1] != get_user_userid(id))
        return PLUGIN_HANDLED

    g_UserDBId[id] = SQL_GetInsertId(query)
    set_task(10.0, "update_last_seen", TASKID_LASTSEEN + id)

    return PLUGIN_HANDLED
}

public update_last_seen(taskid)
{
    new id = taskid - TASKID_LASTSEEN

    new last_seen = get_systime()
    format(g_Query, charsmax(g_Query), "\
        UPDATE `bio_players` \
        SET `last_seen` = %d, `ip`='%s', `steam_id`='%s' \
        WHERE `id`=%d", last_seen, g_UserIP[id], g_UserAuthID[id], g_UserDBId[id])
    SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)

    return PLUGIN_CONTINUE
}

public client_infochanged(id)
{
    if (!is_user_valid_connected(id))
        return PLUGIN_CONTINUE

    new newname[32]
    get_user_info(id, "name", newname, charsmax(newname))
    new oldname[32]
    get_user_name(id, oldname, charsmax(oldname))

    if (!equal(oldname, newname) && !equal(oldname, ""))
    {
        if (g_UserDBId[id])
        {
            set_task(0.1, "update_last_seen", TASKID_LASTSEEN + id)
        }

        g_UserDBId[id] = 0
        reset_player_statistic(id)
        set_task(0.1, "auth_player", TASKID_AUTHORIZE + id)
    }

    return PLUGIN_CONTINUE
}

public event_infect(id, infector)
{
    if (infector)
    {
        g_Me[infector][ME_INFECT]++
        show_me(infector)

        if (g_UserDBId[id])
        {
            format(g_Query, charsmax(g_Query), "\
                UPDATE `bio_players` \
                SET `infected` = `infected` + 1 \
                WHERE `id`=%d", g_UserDBId[id])
            SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
        }
        if (g_UserDBId[infector])
        {
            format(g_Query, charsmax(g_Query), "\
                UPDATE `bio_players` \
                SET `infect` = `infect` + 1 \
                WHERE `id`=%d", g_UserDBId[infector])
            SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
        }
    }
    else if (g_UserDBId[id])
    {
        format(g_Query, charsmax(g_Query), "\
            UPDATE `bio_players` \
            SET `first_zombie` = `first_zombie` + 1 \
            WHERE `id`=%d", g_UserDBId[id])
        SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
    }

    return PLUGIN_CONTINUE
}

public logevent_endRound()
{
	if (get_playersnum())
	{
        // pause to calculate critical hits
        set_task(0.1, "task_announce_best_human_and_zombie")
	}
}

public task_announce_best_human_and_zombie()
{
    new players[32], playersNum, maxInfectId = 0, maxDmgId = 0
    new maxInfectName[32], maxDmgName[32]
    new extraMaxInfectNum = 0, maxInfectList[32]
    get_players(players, playersNum, "ch")
    for (new i = 0; i < playersNum; i++)
    {
        if (g_Me[players[i]][ME_INFECT] > g_Me[players[maxInfectId]][ME_INFECT])
        {
            maxInfectId = i
            extraMaxInfectNum = 0
            maxInfectList[extraMaxInfectNum] = i
        }
        else if (g_Me[players[i]][ME_INFECT] == g_Me[players[maxInfectId]][ME_INFECT] && (i != 0))
        {
            extraMaxInfectNum++
            maxInfectList[extraMaxInfectNum] = i
        }
        if (g_Me[players[i]][ME_DMG] > g_Me[players[maxDmgId]][ME_DMG])
        {
            maxDmgId = i
        }
    }

    maxInfectId = maxInfectList[random_num(0, extraMaxInfectNum)]
    get_user_name(players[maxInfectId], maxInfectName, charsmax(maxInfectName))
    get_user_name(players[maxDmgId], maxDmgName, charsmax(maxDmgName))

    if (g_Me[players[maxInfectId]][ME_INFECT] ||
        g_Me[players[maxDmgId]][ME_DMG])
    {
        colored_print(0, "^x04***^x01 Лучший человек:^x04 %s^x01  ->  [^x03  %d^x01 дамаги  ]",
            maxDmgName, g_Me[players[maxDmgId]][ME_DMG])
        if (g_Me[players[maxInfectId]][ME_INFECT])
            colored_print(0, "^x04***^x01 Лучший зомби:^x04 %s^x01  ->  [^x03  %d^x01 заражени%s  ]",
                maxInfectName, g_Me[players[maxInfectId]][ME_INFECT],
                set_word_completion(g_Me[players[maxInfectId]][ME_INFECT]))

        // extra
        if (g_UserDBId[players[maxInfectId]])
        {
            new Float:frags
            pev(players[maxInfectId], pev_frags, frags)
            set_pev(players[maxInfectId], pev_frags, frags+1.0)

            format(g_Query, charsmax(g_Query), "\
                UPDATE `bio_players` \
                SET `best_zombie` = `best_zombie` + 1 \
                WHERE `id`=%d", g_UserDBId[players[maxInfectId]])
            SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
        }
        if (g_UserDBId[players[maxDmgId]])
        {
            new Float:frags
            pev(players[maxDmgId], pev_frags, frags)
            set_pev(players[maxDmgId], pev_frags, frags+1.0)

            format(g_Query, charsmax(g_Query), "\
                UPDATE `bio_players` \
                SET `best_human` = `best_human` + 1 \
                WHERE `id`=%d", g_UserDBId[players[maxDmgId]])
            SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
        }
    }
}

public event_newround()
{
    new players[32], playersNum
    get_players(players, playersNum, "ch")
    for (new i = 0; i < playersNum; i++)
        reset_player_statistic(players[i])

    if(get_playersnum() && !get_cvar_float("mp_timelimit"))  // galileo
    {
        new Float:player_total[33]
        new player_total_max = 0
        new best_id = 0

        for (new i = 0; i < playersNum; i++)
        {
            new id = players[i]
            new frags, deaths

            frags = get_user_frags(id)
            deaths = fm_get_user_deaths(id)
            player_total[i] = float(frags) / (float(deaths) + 4.0)
            if (player_total[i] >= player_total[player_total_max])
            {
                player_total_max = i
                best_id = id
            }
        }

        set_task(8.0, "task_announce_best_player", best_id)

        if (g_UserDBId[best_id])
        {
            format(g_Query, charsmax(g_Query), "\
                UPDATE `bio_players` \
                SET `best_player` = `best_player` + 1 \
                WHERE `id`=%d", g_UserDBId[best_id])
            SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
        }
    }
}

public task_announce_best_player(best_id)
{
    new best_name[32]
    get_user_name(best_id, best_name, charsmax(best_name))
/*
    colored_print(0, "^x04***^x01 Поздравляем!", best_name)
    colored_print(0, "^x04***^x01 Лучшим игроком карты признан^x03 %s^x01", best_name)
*/
    set_hudmessage(_, _, _, _, _, _, _, 8.0)
    ShowSyncHudMsg(0, CreateHudSyncObj(), "Лучший игрок карты^n^n %s", best_name)
}

public fw_HamKilled(victim, attacker, shouldgib)
{
    new type[16]
    new killer_frags = 1

    g_isalive[victim] = false

    if (g_UserDBId[victim] && is_user_valid_connected(attacker))
    {
        format(g_Query, charsmax(g_Query), "\
            UPDATE `bio_players` \
            SET `death` = `death` + 1 \
            WHERE `id`=%d", g_UserDBId[victim])
        SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
    }

    if (victim == attacker || !is_user_valid_connected(attacker))
    {
        type = "suicide"
    }
    else if (is_user_zombie(attacker))
    {
        type = "infect"
        g_Me[attacker][ME_INFECT]++
    }
    else
    {
        show_me(attacker)

        if (is_user_zombie(victim))
        {
            type = "zombiekills"

            if(get_user_weapon(attacker) == CSW_KNIFE)
            {
                // extra
                format(g_Query, charsmax(g_Query), "\
                    UPDATE `bio_players` \
                    SET `knife_kills` = `knife_kills` + 1 \
                    WHERE `id`=%d", g_UserDBId[attacker])
                SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
            }
        }
    }

    if (is_user_valid_connected(attacker) && g_UserDBId[attacker])
    {
        format(g_Query, charsmax(g_Query), "\
            UPDATE `bio_players` \
            SET `%s` = `%s` + %d \
            WHERE `id`=%d",
            type, type, killer_frags, g_UserDBId[attacker])
        SQL_ThreadQuery(g_SQL_Tuple, "threadQueryHandler", g_Query)
    }

    return HAM_IGNORED
}

public fw_SpawnPlayer(id)
{
    if(!is_user_alive(id))
        return HAM_IGNORED

    g_isalive[id] = true

    return HAM_IGNORED
}

public fw_TakeDamage(victim, inflictor, attacker, Float:damage, damage_type)
{
    if (victim == attacker ||
        !is_user_valid_alive(attacker) ||
        !is_user_valid_connected(victim) ||
        !is_user_zombie(victim)
        )
        return HAM_IGNORED

    if (is_user_valid_alive(attacker) && !is_user_zombie(attacker))
        g_Me[attacker][ME_DMG] += floatround(damage)

    return HAM_IGNORED
}

reset_player_statistic(id)
{
	for (new i = 0; i < ME_NUM; i++)
		g_Me[id][i] = 0
}

public handleSay(id)
{
    new args[64]

    read_args(args, charsmax(args))
    remove_quotes(args)

    new arg1[16]
    new arg2[32]

    argbreak(args, arg1, charsmax(arg1), arg2, charsmax(arg2))
    if (equal(arg1, "/me"))
    {
        show_me(id)
        return PLUGIN_HANDLED
    }
    else if (equal(arg1, "/rank"))
    {
        show_rank(id, arg2)
        return PLUGIN_HANDLED
    }
    else if (equal(arg1, "/rankstats") || equal(arg1, "/stats"))
    {
        show_stats(id)
        return PLUGIN_HANDLED
    }
    else if (equal(arg1, "/top", 4))
    {
        if (arg1[4])
            show_top(id, str_to_num(arg1[4]))
        else
            show_top(id, DEFAULT_TOP_COUNT)
        return PLUGIN_HANDLED
    }

    return PLUGIN_CONTINUE
}

show_me(id)
{
    if (!is_user_zombie(id))
        colored_print(id, "^x04***^x01 Нанес^x04 %d^x01 дамаги",
            g_Me[id][ME_DMG])
    else
        colored_print(id, "^x04***^x01 Заразил^x04 %d^x01 человек%s",
            g_Me[id][ME_INFECT],
            0 < g_Me[id][ME_INFECT] < 5 ? "а" : "")

    return PLUGIN_HANDLED
}

show_rank(id, unquoted_whois[])
{
    if (!unquoted_whois[0])
    {
        format(g_Query, charsmax(g_Query), "\
            SELECT *,(SELECT COUNT(*) FROM `bio_players`) AS `total` \
            FROM %s WHERE `id`=%d",
            g_select_statement, g_UserDBId[id])
    }
    else
    {
        mysql_escape_string(unquoted_whois, 31)
        copy(whois, 31, unquoted_whois)

        format(g_Query, charsmax(g_Query), "\
            SELECT *,(SELECT COUNT(*) FROM `bio_players`) AS `total` \
            FROM %s \
            WHERE `nick` LIKE BINARY '%%%s%%' LIMIT 1",
            g_select_statement, whois)
    }

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)

    SQL_ThreadQuery(g_SQL_Tuple, "ShowRank_QueryHandler", g_Query, data, 2)

    return PLUGIN_HANDLED
}

public ShowRank_QueryHandler(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
    new id = data[0]

    if(FailState)
    {
        new szQuery[1024]
        SQL_GetQueryString(query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 3)
        colored_print(id, "^x04***^x01 Команда^x04 /rank^x01 временно недоступна")
        return PLUGIN_HANDLED
    }

    if (data[1] != get_user_userid(id))
        return PLUGIN_HANDLED

    new name[32]
    new rank
    new Float:res
    new total

    if (SQL_MoreResults(query))
    {
    	SQL_ReadResult(query, column("nick"), name, charsmax(name))
    	rank = SQL_ReadResult(query, column("rank"))
        SQL_ReadResult(query, column("skill"), res)
        total = SQL_ReadResult(query, column("total"))

    	colored_print(id, "^x04***^x03 %s^x01 находится на^x04 %d^x01 из %d позиций!",
            name, rank, total)
    }
    else
    	colored_print(id, "^x04*** Игрок^x03 %s^x01 не найден. Проверь заглавные буквы!", whois)

    return PLUGIN_HANDLED
}

show_stats(id)
{
    colored_print(id, "^x04***^x01 Подробная статистика^x04 http://gozm.myarena.ru/top.php")
}

show_top(id, top)
{
    format(g_Query, charsmax(g_Query), "SELECT COUNT(*) FROM `bio_players`")
    new data[3]
    data[0] = id
    data[1] = get_user_userid(id)
    data[2] = top
    SQL_ThreadQuery(g_SQL_Tuple, "ShowTop_QueryHandler_Part1", g_Query, data, 3)

    return PLUGIN_HANDLED
}

public ShowTop_QueryHandler_Part1(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
    new id = data[0]

    if(FailState)
    {
        new szQuery[1024]
        SQL_GetQueryString(query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 5)
        colored_print(id, "^x04***^x01 Команда^x04 /top^x01 временно недоступна")
        return PLUGIN_HANDLED
    }

    if (data[1] != get_user_userid(id))
    	return PLUGIN_HANDLED

    if(!SQL_MoreResults(query))
    {
        colored_print(id, "^x04***^x01 Команда^x04 /top^x01 временно недоступна")
        return PLUGIN_HANDLED
    }

    new count
    count = SQL_ReadResult(query, 0)

    new top = data[2]
    if (top <= DEFAULT_TOP_COUNT)
        top = DEFAULT_TOP_COUNT
    if (top >= count)
        top = count

    format(g_Query, charsmax(g_Query), "\
        SELECT `nick`, `rank`, `skill` \
        FROM %s \
        WHERE `rank` <= %d ORDER BY `rank` ASC LIMIT %d, %d",
        g_select_statement, top, top - DEFAULT_TOP_COUNT, DEFAULT_TOP_COUNT)
    new more_data[4]
    more_data[0] = data[0]
    more_data[1] = data[1]
    more_data[2] = data[2]
    more_data[3] = count
    SQL_ThreadQuery(g_SQL_Tuple, "ShowTop_QueryHandler_Part2", g_Query, more_data, 4)

    return PLUGIN_HANDLED
}

public ShowTop_QueryHandler_Part2(FailState, Handle:query, error[], err, data[], size, Float:querytime)
{
    new id = data[0]

    if(FailState)
    {
        new szQuery[1024]
        SQL_GetQueryString(query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 6)
        colored_print(id, "^x04***^x01 Команда^x04 /top^x01 временно недоступна")

        return PLUGIN_HANDLED
    }

    if (data[1] != get_user_userid(id))
    	return PLUGIN_HANDLED

    new title[32]
    new top = data[2]

    new count = data[3]
    if (top <= DEFAULT_TOP_COUNT)
        format(title, 31, "ТОП игроков 1-%d", top)
    else if (top < count)
        format(title, 31, "ТОП игроков %d-%d", top - DEFAULT_TOP_COUNT + 1, top)
    else
    {
        top = count
        format(title, 31, "ТОП игроков %d-%d ", top - DEFAULT_TOP_COUNT + 1, top)
    }

    new iLen = 0
    setc(g_text, MAX_BUFFER_LENGTH + 1, 0)

    iLen = format_all_themes(g_text, iLen, id)
    iLen += format(g_text[iLen], MAX_BUFFER_LENGTH - iLen,
        "<body><table width=100%% border=0 align=center cellpadding=0 cellspacing=1>")


    new lNick[32], lResult[32]
    format(lNick, 31, "Ник")
    format(lResult, 31, "Скилл")
    iLen += format(g_text[iLen], MAX_BUFFER_LENGTH - iLen,
        "<body><tr><th>%s<th>%s<th>%s</tr>", "#", lNick, lResult)

    new name[32], rank, skill
    new Float:pre_skill
    gb_css_trigger = true

    while (SQL_MoreResults(query))
    {
        rank = SQL_ReadResult(query, column("rank"))
        SQL_ReadResult(query, column("nick"), name, charsmax(name))
        SQL_ReadResult(query, column("skill"), pre_skill)
        skill = floatround(pre_skill*1000.0)

        iLen += format(g_text[iLen], MAX_BUFFER_LENGTH - iLen,
            "<tr%s><td>%d<td>%s<td>%d</tr>", gb_css_trigger ? "" : " id=c", rank, name, skill)

        SQL_NextRow(query)
        gb_css_trigger = gb_css_trigger ? false : true
    }

    show_motd(id, g_text, title)

    setc(g_text, MAX_BUFFER_LENGTH + 1, 0)

    return PLUGIN_HANDLED
}

public threadQueryHandler(FailState, Handle:Query, error[], err, data[], size, Float:querytime)
{
    if(FailState)
    {
        new szQuery[512]
        SQL_GetQueryString(Query, szQuery, charsmax(szQuery))
        MySqlX_ThreadError(szQuery, error, err, FailState, floatround(querytime), 99)
    }

    return PLUGIN_HANDLED
}

/*********  Error handler  ***************/
MySqlX_ThreadError(szQuery[], error[], errnum, failstate, request_time, id)
{
    if (failstate == TQUERY_CONNECT_FAILED)
    {
        log_amx("[BIO STAT]: Connection failed")
    }
    else if (failstate == TQUERY_QUERY_FAILED)
    {
        log_amx("[BIO STAT]: Query failed")
    }
    log_amx("[BIO STAT]: Called from id=%d, errnum=%d, error=%s", id, errnum, error)
    log_amx("[BIO STAT]: Query: %ds to '%s'", request_time, szQuery)
}

format_all_themes(sBuffer[MAX_BUFFER_LENGTH + 1], iLen, player_id)
{
    //new iDesign = get_pcvar_num(g_pcvar_design)
    new iDesign = player_id % 4
    switch(iDesign)
    {
        case 0:
            iLen = format(sBuffer, MAX_BUFFER_LENGTH, STATSX_SHELL_DESIGN3_STYLE)
        case 1:
            iLen = format(sBuffer, MAX_BUFFER_LENGTH, STATSX_SHELL_DESIGN7_STYLE)
        case 2:
            iLen = format(sBuffer, MAX_BUFFER_LENGTH, STATSX_SHELL_DESIGN8_STYLE)
        case 3:
            iLen = format(sBuffer, MAX_BUFFER_LENGTH, STATSX_SHELL_DESIGN10_STYLE)
        default:
            iLen = format(sBuffer, MAX_BUFFER_LENGTH, STATSX_SHELL_DESIGN10_STYLE)
    }

    return iLen
}

set_word_completion(number)
{
    new word_completion[8]
    if (number == 0 || number > 4)
        word_completion = "й"
    else if (number == 1)
        word_completion = "е"
    else
        word_completion = "я"

    return word_completion
}

mysql_escape_string(dest[], len)
{
    replace_all(dest, len, "\\", "\\\\")
    replace_all(dest, len, "\0", "\\0")
    replace_all(dest, len, "\n", "\\n")
    replace_all(dest, len, "\r", "\\r")
    replace_all(dest, len, "\x1a", "\Z")
    replace_all(dest, len, "'", "\'")
    replace_all(dest, len, "^"", "\^"")
}

fm_get_user_deaths(id)
{
	// Prevent server crash if entity is not safe for pdata retrieval
	if (pev_valid(id) != PDATA_SAFE)
		return 0;

	return get_pdata_int(id, OFFSET_DEATH);
}
