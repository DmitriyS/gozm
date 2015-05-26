#include <amxmodx>
#include <regex>
#include <colored_print>

public plugin_init()
{
    register_plugin("Anti-Spam", "1.3", "GoZm")

    register_clcmd("say", "check_player_msg")
    register_clcmd("say_team", "check_player_msg")
}

bool:is_invalid(const text[])
{
    new error[50], num
    new Regex:regex = regex_match(text, "[a-z0-9-]{3,}\.[a-z]{1,2}(\S)", num, error, 49, "i")
    if(regex >= REGEX_OK)
    {
        regex_free(regex)
        return true
    }
    regex = regex_match(text, "([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}", num, error, 49)
    if(regex >= REGEX_OK)
    {
        regex_free(regex)
        return true
    }
    regex = regex_match(text, "27[0-9][0-9][0-9]", num, error, 49)
    if(regex >= REGEX_OK)
    {
        regex_free(regex)
        return true
    }
    if (containi(text, "ICQ") != -1)
        return true
    if (containi(text, "ManoCS") != -1)
        return true
    if (equali(text[strlen(text)-4], "107^""))
        return true
    if (equali(text[strlen(text)-4], "108^""))
        return true
    if (equali(text, "/xmenu"))
        return true
    if (equali(text, "/cp"))
        return true
    if (equali(text, "/knife"))
        return true

    return false
}

public check_player_msg(id)
{
    new text[128]
    read_args(text,127)
    remove_quotes(text)

    if(is_invalid(text))
    {
        colored_print(id, "^x04***^x01 [%s] -^x04 СПАМ, СООБЩЕНИЕ УДАЛЕНО!", text)
        return PLUGIN_HANDLED
    }

    return PLUGIN_CONTINUE
}
