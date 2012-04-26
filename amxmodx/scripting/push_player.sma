/* Plugin generated by AMXX-Studio */

#include <amxmodx>
#include <amxmisc>
#include <engine>

#define PLUGIN "Push player"
#define VERSION "1.0"
#define AUTHOR "OneEyed & Sn!ff3r"

new cvar

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	cvar = register_cvar("amx_moveplayer", "1")
	
	register_touch("player", "player", "touchtouch")	
}

public touchtouch(player, player2)
{
	if(get_pcvar_num(cvar))
	{
		if((!(task_exists(player * 1000 + player2))) && (!(task_exists(player2 * 1000 + player))))
		{
			new Float:speed[2][3]
			new Float:over_speed[3]
			
			set_task(0.2, "empty_space", player * 1000 + player2)
			set_task(0.2, "empty_space", player2 * 1000 + player)
			
			entity_get_vector(player, EV_VEC_velocity, speed[0])
			entity_get_vector(player2, EV_VEC_velocity, speed[1])
			
			for(new i = 0; i < 3; i++)
			{
				over_speed[i] = speed[0][i] + speed[1][i]
				speed[0][i] += over_speed[i] * 0.65
				speed[1][i] -= over_speed[i] * 0.65
			}
			entity_set_vector(player, EV_VEC_velocity, speed[0])
			entity_set_vector(player2, EV_VEC_velocity, speed[1])
		}
	}
}

public empty_space() {}
