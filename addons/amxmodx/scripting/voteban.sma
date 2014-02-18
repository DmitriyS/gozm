#include <amxmodx>
#include <amxmisc>
#include <colored_print>

#define MAX_players 32
#define MAX_menudata 1024

#define MPROP_BACKNAME  2
#define MPROP_NEXTNAME  3
#define MPROP_EXITNAME  4

new ga_PlayerName[MAX_players][32]
new ga_PlayerAuthID[MAX_players][35]
new ga_PlayerID[MAX_players]
new ga_PlayerUserID[MAX_players]
new ga_PlayerIP[MAX_players][16]
new gi_VoteStarter
new gi_MenuPosition
new gi_Sellection
new gi_TotalPlayers
new i
//pcvars
new gi_BanTime

new ban_reason[128]

public plugin_init()
{
    register_plugin("voteban menu","1.2","hjvl")
    register_clcmd("say","SayIt" )
    register_clcmd("say_team","SayIt" )
    register_clcmd("VIP_REASON", "setCustomBanReason")
    register_menucmd(register_menuid("ChoosePlayer"), 1023, "ChooseMenu")

    gi_BanTime=register_cvar("amxx_voteban_bantime","30")
}

public SayIt(id)
{
    static say_args[11]
    read_args(say_args, 10)
    remove_quotes(say_args)

    if(say_args[0] == '/' && containi(say_args, "voteban") != -1)
    {
        if(get_user_flags(id) & ADMIN_BAN) {
            colored_print(id,"^x04***^x01 Use AdminMenu!")
            return PLUGIN_HANDLED_MAIN
        }
        if(get_user_flags(id) & ADMIN_LEVEL_H) {
            colored_print(id,"^x04***^x01 Use^x04 /ban")
            return PLUGIN_HANDLED_MAIN
        }
        else {
            colored_print(id,"^x04***^x01 Only VIP-players can use^x04 /voteban")
            return PLUGIN_HANDLED_MAIN
        }
        
    }
    
    else if(say_args[0] == '/' && equali(say_args, "/ban")) {
        if(get_user_flags(id) & ADMIN_BAN) {
            colored_print(id,"^x04***^x01 Use AdminMenu!")
            return PLUGIN_HANDLED_MAIN
        }
        if(get_user_flags(id) & ADMIN_LEVEL_H) {
            get_players( ga_PlayerID, gi_TotalPlayers )
            for(i=0; i<gi_TotalPlayers; i++)
            {
                new TempID = ga_PlayerID[i]

                if(TempID == id)
                    gi_VoteStarter=i

                get_user_name( TempID, ga_PlayerName[i], 31 )
                get_user_authid( TempID, ga_PlayerAuthID[i], 34 )
                get_user_ip( TempID, ga_PlayerIP[i], 15, 1 )
                ga_PlayerUserID[i] = get_user_userid(TempID)
            }

            gi_MenuPosition = 0
            ShowPlayerMenu(id)
            return PLUGIN_HANDLED_MAIN
        }
        else
        {
            colored_print(id,"^x04***^x01 Only VIP-players can use ^x04/ban")
            return PLUGIN_HANDLED_MAIN
        }
    }

    return PLUGIN_CONTINUE
}

public ShowPlayerMenu(id)
{
    if(gi_MenuPosition < 0)  
        return

    new start = gi_MenuPosition * 8
    if(start >= gi_TotalPlayers)
            start = gi_MenuPosition

    new end = start + 8
    if(end > gi_TotalPlayers)
            end = gi_TotalPlayers

    static menubody[512]	
    new len = format(menubody, 511, "Players to \rBAN: \w^n^n")

    static name[32]

    new b = 0, i
    new keys = MENU_KEY_0

    for(new a = start; a < end; ++a)
    {
        i = ga_PlayerID[a]
        get_user_name(i, name, 31)

        if( i == id || get_user_flags(i) & ADMIN_LEVEL_H)
        {
            ++b
            len += format(menubody[len], 511 - len, "\d#  %s\w^n", name)
        }
        else
        {
            keys |= (1<<b)
            len += format(menubody[len], 511 - len, "%d. %s\w^n", ++b, name)
        }
    }

    if(end != gi_TotalPlayers) 
    {
            format(menubody[len], 511 - len, "^n9. %s...^n0. %s", "Next", gi_MenuPosition ? "Back" : "Exit")
            keys |= MENU_KEY_9
    }
    else
        format(menubody[len], 511-len, "^n0. %s", gi_MenuPosition ? "Back" : "Exit")

    show_menu(id, keys, menubody, 20, "ChoosePlayer")
}

public ChooseMenu(id, key)
{
  switch(key)
  {
    case 8:
    {
      gi_MenuPosition=gi_MenuPosition+8
      ShowPlayerMenu(id)
    }
    case 9:
    {
      if(gi_MenuPosition>=8)
      {
        gi_MenuPosition=gi_MenuPosition-8
        ShowPlayerMenu(id)
      }
      else
        return 0
    }
    default:
    {
        gi_Sellection=gi_MenuPosition+key
        chooseBanReason(id)
    }
  }
  return PLUGIN_HANDLED
}

public chooseBanReason(id)
{
    new i_Menu = menu_create("\yChoose Reason", "reason_menu_handler" )

    menu_additem(i_Menu, "WallHack", "20160")
    menu_additem(i_Menu, "SpeedHack & AIM", "40320")
    menu_additem(i_Menu, "Block", "15")
    menu_additem(i_Menu, "Reconnect", "15")
    menu_additem(i_Menu, "Razbil kamni/doski", "15")
    menu_additem(i_Menu, "Mat", "60")
    menu_additem(i_Menu, "Obxod", "1440")
    menu_additem(i_Menu, "Nick", "10")
    menu_additem(i_Menu, "Microphone", "30")
    menu_additem(i_Menu, "Black List", "40320")
    menu_additem(i_Menu, "Noob", "30")
    menu_additem(i_Menu, "Custom", "1")
    
    menu_setprop(i_Menu, 2, "Back")
    menu_setprop(i_Menu, 3, "Next")
    menu_setprop(i_Menu, 4, "Close")

    menu_display(id, i_Menu, 0)

    return PLUGIN_HANDLED
}

public reason_menu_handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }

    new s_Data[6], s_Name[64], i_Access, i_Callback
    menu_item_getinfo(menu, item, i_Access, s_Data, charsmax(s_Data), s_Name, charsmax(s_Name), i_Callback)
    new ban_length = str_to_num(s_Data)
    
    if(ban_length == 1)
        client_cmd(ga_PlayerID[gi_VoteStarter], "messagemode VIP_REASON")
    else
        ActualBan(ban_length, s_Name)

    return PLUGIN_HANDLED; 
}

public setCustomBanReason(id,level,cid)
{
    new szReason[128]
    read_argv(1, szReason, 127)
    copy(ban_reason, 127, szReason)
    if(strlen(ban_reason) == 0) {
        colored_print(id,"^x04***^x01 Empty ban reason! Not a deal.")
        return PLUGIN_HANDLED
    }

    ActualBan(get_pcvar_num(gi_BanTime), ban_reason)

    return PLUGIN_HANDLED
}

public additionalBan() {
    client_cmd(ga_PlayerID[gi_VoteStarter], "amx_superban #%d %d %s", ga_PlayerUserID[gi_Sellection], get_pcvar_num(gi_BanTime), ban_reason)
}

public ActualBan(time, reason[])
{
    client_cmd(ga_PlayerID[gi_VoteStarter], "amx_ban %d #%d %s", time, ga_PlayerUserID[gi_Sellection], reason)
//    colored_print(0, "ALL: amx_ban %d #%d %s", time, ga_PlayerUserID[gi_Sellection], reason)
//    colored_print(ga_PlayerID[gi_VoteStarter], "ID: amx_ban %d #%d %s", time, ga_PlayerUserID[gi_Sellection], reason)

    colored_print(0,"^x03%s ^x01is BANNED by %s! Reason: %s", ga_PlayerName[gi_Sellection], ga_PlayerName[gi_VoteStarter], reason)
    return 0
}